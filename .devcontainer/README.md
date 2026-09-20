# Development container

Everything this repository needs to develop and verify it locally, inside a
container: every hook in `.pre-commit-config.yaml` (including
`actionlint-docker`, which starts a container of its own), `gh`, and `git`
pushes over SSH. It is built on the organization's base image from
[ivan-pinatti-labs/devcontainer-images](https://github.com/ivan-pinatti-labs/devcontainer-images),
whose `docs/IMAGES.md` explains the image itself.

It runs with rootless Podman, and SELinux stays enforcing the whole time.

## Before the first start

Two things live on the host, outside any container, and are set up once.
Both are shared by every repository that uses this development container, so
a machine that already has them skips this section.

### A GitHub token for `gh`

A fine-grained personal access token for the `ivan-pinatti-labs` organization
with read and write access to pull requests and issues, and read access to
actions, commit statuses and contents. Nothing else: no administration,
secrets or organization permissions. Store it as a Podman secret:

```shell
podman secret create gh-devcontainer /path/to/a/file/holding/the/token
```

Delete that file afterwards. The container receives the token as `GH_TOKEN`;
it never appears in `podman inspect`.

### An SSH agent for `git push`

A dedicated SSH key, not your usual one, held by an ssh-agent that runs in its
own container. The development container can ask that agent to sign a GitHub
login but never sees the key, and the key is restricted to GitHub, so nothing
running in the development container can use it anywhere else.

Create the key with a passphrase and add its public half to your GitHub
account as an authentication key:

```shell
ssh-keygen -t ed25519 -C devcontainer -f ~/.ssh/devcontainer/id_ed25519
chmod 700 ~/.ssh/devcontainer
```

Start the agent container. It has no network, no capabilities and a read
only filesystem, and it runs in the same SELinux domain and category as the
development container, which is what allows the two to talk:

```shell
mkdir -p "${XDG_RUNTIME_DIR}/devcontainer-ssh"
chmod 700 "${XDG_RUNTIME_DIR}/devcontainer-ssh"
curl -fsS https://api.github.com/meta \
  | jq -r '.ssh_keys[] | "github.com " + .' \
  > "${XDG_RUNTIME_DIR}/devcontainer-ssh/known_hosts"
podman run -d --name devcontainer-ssh-agent \
  --network=none --cap-drop=all --read-only \
  --security-opt no-new-privileges \
  --userns=keep-id \
  --security-opt label=type:container_engine_t \
  --security-opt label=level:s0:c555,c666 \
  -v "${XDG_RUNTIME_DIR}/devcontainer-ssh:/sock:Z" \
  -v "${HOME}/.ssh/devcontainer:/key:ro,Z" \
  ghcr.io/ivan-pinatti-labs/devcontainer-base@sha256:422d159cc15e46e4ae806bcf718d63ea5bd080fa701ab7a980e45b55d955b602 \
  ssh-agent -D -a /sock/agent.sock
```

Then unlock the key once per login, typing the passphrase:

```shell
podman exec -it -e SSH_AUTH_SOCK=/sock/agent.sock devcontainer-ssh-agent \
  ssh-add -H /sock/known_hosts -h github.com /key/id_ed25519
```

GitHub's host keys come from GitHub's own API rather than from a first
connection, so the development container verifies the host strictly.

## Starting it

Open the repository's main clone as a folder of its own, and choose **Reopen
in Container**.

- Not a worktree. Worktrees created inside the container work normally, but a
  worktree opened directly does not, because its git metadata lives in the
  main clone, outside the folder that gets mounted.
- Not inside a multi-root workspace (a window titled "Untitled (Workspace)").
  There the Dev Containers extension does not find this configuration, and
  offers to add a new one to the workspace or to the user data folder
  instead. Neither is this one; open the folder by itself.

## Why each run argument

| Argument | Why |
| --- | --- |
| `--userns=keep-id:uid=1000,gid=1000` | Maps your host account to the container's `dev` account, so files in the mounted clone stay yours. The uid is spelled out because plain `keep-id` maps your account to the same number inside, which lines up with `dev` only when your own uid happens to be 1000. |
| `label=type:container_engine_t` | The confined SELinux domain that allows a container engine to run inside, so the hooks that start containers (`actionlint-docker` here) work without turning SELinux labeling off. |
| `label=level:s0:c555,c666` | The same SELinux category as the ssh-agent container; a different category cannot connect to its socket. |
| `--device /dev/fuse` | The nested container storage driver needs it. |
| `--secret gh-devcontainer,...` | The GitHub token, as `GH_TOKEN`. |
| The workspace mount at the clone's own path | Paths inside the container match the host, so git worktree metadata and the bind mounts hooks make resolve the same way in both. |
| The `devcontainer-ssh` mount | The ssh-agent socket and GitHub's host keys. |

## What it runs

```shell
pre-commit install
pre-commit run --all-files
```

Tools come from signed package repositories, installed in
`.devcontainer/Dockerfile`: `pre-commit` from Ubuntu's own archive, `gh` from
GitHub's, whose signing key the base image checks against a fingerprint and
installs without enabling the repository. A tool this repository does not
install is missing in the container rather than borrowed from somewhere else,
which is how a missing dependency shows up.

There is no version manager and no `.tool-versions`. Package versions are
deliberately unpinned, because Ubuntu and these vendors ship security fixes
by moving a version inside a release. What is pinned is the base image
digest, which Renovate keeps current.

Rebuilding can therefore give you different package versions than it did last
week, by design. The digest pins what the container builds on, not what apt
resolves on top. If you need the exact container you had before, keep the
built image rather than expecting a rebuild to reproduce it. The base image's
`docs/TOOL_SOURCES.md` has the source line for each repository it carries a
key for, and the reasoning behind all of this.
