# Developing in containers

This repository is developed with
[devcontainer-airlock](https://github.com/ivan-pinatti-labs/devcontainer-airlock):
you and the coding agents work in a workbench that holds no GitHub token and
no ssh key, and every hook, test and package install runs in an L2
container that gets the working tree and nothing else. Its
[docs/LAYERS.md](https://github.com/ivan-pinatti-labs/devcontainer-airlock/blob/main/docs/LAYERS.md)
explains the layers and the one time setup on the host (a podman secret for
the GitHub token, a dedicated ssh key, and the settings file).

## Daily use

Clone devcontainer-airlock next to this repository's main clone (or point
`WORKBENCH_HOME` at a clone elsewhere), and the Makefile here gains its
targets:

```shell
make unlock          # the ssh key, for eight hours
make claude          # Claude Code in its workbench, started if needed
make codex           # Codex in its own workbench
make claude-shell    # a terminal in that workbench (or codex-shell)
```

`make` alone lists them. For the editor, attach VS Code to
`workbench-claude-<folder>` or `workbench-codex-<folder>` (**Dev Containers:
Attach to Running Container**). The first time, inside a workbench, route
this repository's git hooks through L2:

```shell
l2-hooks-install
```

## What is in here

| File | What |
| --- | --- |
| `l2/Dockerfile` | This repository's L2 image, on the shared one pinned by digest. A project adds the tools its hooks and tests need here. `l2` builds it in the L2 engine the first time and whenever it changes; Renovate keeps the digest current. |
| `egress-sets` | The network services the egress proxy allows for this repository, one per line. |

Tools come from signed package repositories: prefer a distribution package,
then a vendor's own signed apt repository, then the tool's official container
image. Package versions are deliberately unpinned, because Ubuntu and these
vendors ship security fixes by moving a version inside a release. What is
pinned is the image digest, which fixes what the image builds on, not what apt
resolves on top.
