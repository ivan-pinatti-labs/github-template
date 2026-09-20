# Tasks for this repository. A project created from this template keeps the
# `shell` target and adds its own alongside it.
#
# checkmake reads only the first physical line of a .PHONY declaration and
# silently drops backslash continuations, so every .PHONY here is written on
# one line. Splitting one across lines leaves the trailing targets invisible
# to it, and the phonydeclared and minphony rules then report them as
# undeclared. Tracked upstream as checkmake#280.
.PHONY: all help shell

# Bare `make` shows the target list rather than doing something surprising.
# checkmake's minphony rule also wants `all` declared phony; see checkmake.ini.
all: help

help:
	@printf '%s\n' \
		'Usage:' \
		'  make <target>' \
		'' \
		'Targets:' \
		'  help                        Show this message.' \
		'  shell                       Open a shell inside the development container.' \
		'' \
		'Variables:' \
		'  DEV_IMAGE                   Tag for the development image.' \
		'  SHELL_EXTRA_MOUNTS          Extra podman -v arguments for `make shell`.'

# A shell inside the development container, without an editor in the loop.
#
# The flags mirror .devcontainer/devcontainer.json's runArgs, deliberately
# and by hand: a devcontainer.json is read by editors and by the devcontainer
# CLI, neither of which is involved here, so the two lists have to be kept in
# step. Anything added there that this target needs belongs here too.
#
# container_engine_t and /dev/fuse are what let the nested runtime work under
# SELinux, for the hooks that start containers of their own (hadolint-docker,
# actionlint-docker). See docs/IMAGES.md in
# ivan-pinatti-labs/devcontainer-images, under "Running containers inside it".
#
# The two agent directories are bind mounted from the host so Claude Code and
# Codex read and write the same sessions, transcripts and credentials whether
# they run in here or on the host, and so none of it is lost when the
# container exits.
#
# Lowercase z on those two, uppercase Z on the working tree, and the
# difference matters. Z labels a mount private to a single container, which
# is right for a working tree this container alone uses. The agent
# directories are used by the host's own agents and by every other
# repository's development container, so labelling them private would take
# them away from all of those. z is the shared label.
#
# SHELL_EXTRA_MOUNTS exists because a bind mount carries a symlink across as
# a symlink. Anything under ~/.claude or ~/.codex pointing outside those
# directories dangles in here until its target is mounted too, which is a per
# machine detail and so a variable rather than a path committed to a public
# repository:
#
#   make shell SHELL_EXTRA_MOUNTS='-v /path/on/host:/path/on/host:rw,z'
DEV_IMAGE ?= github-template-dev
SHELL_EXTRA_MOUNTS ?=

# GH_TOKEN by the mechanism devcontainer.json uses where that is available,
# and by the ordinary environment where it is not.
#
# devcontainer.json passes `--secret gh-devcontainer,type=env,target=GH_TOKEN`,
# which reads a podman secret rather than the caller's environment. That is
# the better of the two: a secret does not appear in the container's
# configuration, so it stays out of `podman inspect` the way an `-e` value
# does not.
#
# It cannot be used unconditionally. `--secret` naming a secret that does not
# exist does not degrade, it aborts the run with "no secret with name or id",
# so hard coding it would break `make shell` on any machine that has not run
# `podman secret create gh-devcontainer`, which is every fresh clone.
#
# The environment fallback stays conditional on GH_TOKEN being non-empty,
# because `-e GH_TOKEN` with nothing set exports an empty GH_TOKEN, which gh
# treats as a token and fails on rather than falling back to unauthenticated.
_comma := ,
_shell_gh_secret := $(shell podman secret exists gh-devcontainer >/dev/null 2>&1 && echo present)
_shell_gh_token := $(if $(_shell_gh_secret),\
--secret=gh-devcontainer$(_comma)type=env$(_comma)target=GH_TOKEN,\
$(if $(GH_TOKEN),-e GH_TOKEN,))

# The ssh-agent socket the devcontainer expects, mounted only if the host has
# actually set one up. Without it the container simply has no agent, which is
# a working shell with no git-over-ssh, rather than a bind mount of a path
# that does not exist and a container that refuses to start.
_shell_ssh_dir := $(XDG_RUNTIME_DIR)/devcontainer-ssh
_shell_ssh := $(if $(wildcard $(_shell_ssh_dir)),\
-v "$(_shell_ssh_dir):/run/devcontainer-ssh:rw,z" \
-e SSH_AUTH_SOCK=/run/devcontainer-ssh/agent.sock \
-e GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/run/devcontainer-ssh/known_hosts -o StrictHostKeyChecking=yes",)

shell:
	@echo "Building the development container..."
	@podman build --file .devcontainer/Dockerfile --tag $(DEV_IMAGE) .
	@mkdir -p "$(HOME)/.claude" "$(HOME)/.codex"
	@echo "Entering $(DEV_IMAGE). Type exit to leave."
	@podman run --rm --interactive --tty \
		--userns=keep-id:uid=1000,gid=1000 \
		--security-opt label=type:container_engine_t \
		--security-opt label=level:s0:c555,c666 \
		--device /dev/fuse \
		-v "$(CURDIR):$(CURDIR):rw,Z" \
		-v "$(HOME)/.claude:/home/dev/.claude:rw,z" \
		-v "$(HOME)/.codex:/home/dev/.codex:rw,z" \
		$(_shell_ssh) \
		$(_shell_gh_token) \
		$(SHELL_EXTRA_MOUNTS) \
		--workdir "$(CURDIR)" \
		$(DEV_IMAGE) bash
