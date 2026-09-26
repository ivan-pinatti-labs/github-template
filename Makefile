# Tasks for this repository. A project created from this template keeps the
# workbench targets and adds its own alongside them.
#
# checkmake reads only the first physical line of a .PHONY declaration and
# silently drops backslash continuations, so every .PHONY here is written on
# one line. Splitting one across lines leaves the trailing targets invisible
# to it, and the phonydeclared and minphony rules then report them as
# undeclared. Tracked upstream as checkmake#280.
.PHONY: all help workbench-help

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
		''
	@$(MAKE) --no-print-directory workbench-help
