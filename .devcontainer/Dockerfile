# Development container: everything this repository's hooks need, on top of
# the organization's shared base image. See .devcontainer/README.md for how to
# start it and why each run argument is there.
#
# The base image is pinned by digest. BASE_IMAGE is a build argument only so a
# change to the base image can be tested against this repository before it is
# published.
ARG BASE_IMAGE=ghcr.io/ivan-pinatti-labs/devcontainer-base@sha256:422d159cc15e46e4ae806bcf718d63ea5bd080fa701ab7a980e45b55d955b602
FROM ${BASE_IMAGE}

# A tool the project needs that asdf cannot install (a distribution package,
# for example) goes here, in a step of its own that runs as root and switches
# back to the dev user afterwards.

USER 1000:1000

# Every tool .tool-versions pins, installed from that file. It is copied to a
# scratch directory and removed afterwards rather than left in the home
# directory, where asdf would treat it as a global fallback: a tool this
# repository does not pin should be missing in this container, not silently
# supplied.
COPY --chown=1000:1000 .tool-versions /tmp/tool-versions/.tool-versions
WORKDIR /tmp/tool-versions
RUN while read -r tool _; do asdf plugin add "${tool}"; done < .tool-versions \
  && asdf install \
  && rm -rf /tmp/tool-versions

WORKDIR /workspace
