# Tasks for this repository. A project created from this template keeps the
# workbench targets and adds its own alongside them.
#
# checkmake reads only the first physical line of a .PHONY declaration and
# silently drops backslash continuations, so every .PHONY here is written on
# one line. Splitting one across lines leaves the trailing targets invisible
# to it, and the phonydeclared and minphony rules then report them as
# undeclared. Tracked upstream as checkmake#280.
.PHONY: all help workbench-help cross-review test

# Bare `make` shows the target list rather than doing something surprising.
# checkmake's minphony rule also wants `all` declared phony; see checkmake.ini.
all: help

# The workbench targets (make claude, make codex, make unlock and the rest)
# come from a devcontainer-airlock clone, by default the one next to this
# repository's main clone, so every worktree finds the same one. See
# .devcontainer/README.md.
WORKBENCH_HOME ?= $(abspath $(dir $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null))../devcontainer-airlock)
-include $(WORKBENCH_HOME)/host/workbench.mk

ifeq ($(wildcard $(WORKBENCH_HOME)/host/workbench.mk),)
workbench-help:
	@printf '%s\n' \
		'Workbench: no devcontainer-airlock clone at $(WORKBENCH_HOME).' \
		'  Clone ivan-pinatti-labs/devcontainer-airlock there, or set WORKBENCH_HOME,' \
		'  for make claude, make codex, make unlock and the rest (.devcontainer/README.md).'
endif

help:
	@printf '%s\n' \
		'Usage:' \
		'  make <target>' \
		'' \
		'Targets:' \
		'  help                        Show this message.' \
		'  cross-review                Blind review of this branch by the other vendor'"'"'s agent' \
		'                              (REVIEWER=codex|claude; AGENTS.md, "Review before a pull request").' \
		'  test                        Run the tests under tests/.' \
		''
	@$(MAKE) --no-print-directory workbench-help

# Runs where the reviewer CLIs and their logins are, never in L2: the
# reviewer needs the network and its own credentials. scripts/cross-review.sh
# documents its settings and exit statuses.
cross-review:
	scripts/cross-review.sh

# Every tests/*.test.sh, each as its own bash process.
test:
	@status=0; for t in tests/*.test.sh; do echo "== $$t"; bash "$$t" || status=1; done; exit $$status
