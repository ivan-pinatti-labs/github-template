# Development container: everything this repository's hooks need, on top of
# the organization's shared base image. See .devcontainer/README.md for how to
# start it and why each run argument is there.
#
# The base image is pinned by digest. BASE_IMAGE is a build argument only so a
# change to the base image can be tested against this repository before it is
# published.
ARG BASE_IMAGE=ghcr.io/ivan-pinatti-labs/devcontainer-base@sha256:32c98c5e822a95028b08a6d388374f2a342bd72be33969f04e73aa1efe988044
FROM ${BASE_IMAGE}

# A tool the project needs that asdf cannot install (a distribution package,
# for example) goes here, in a step of its own that runs as root and switches
# back to the dev user afterwards.

USER 1000:1000

# Every asdf plugin, from its repository URL at the commit
# .devcontainer/asdf-plugins pins, never by short name from asdf's plugin
# index. A tool in .tool-versions with no pinned plugin has no plugin at all
# here, so `asdf install` below fails instead of fetching one unreviewed.
COPY --chown=1000:1000 .devcontainer/asdf-plugins /tmp/tool-versions/asdf-plugins
RUN while read -r name url _ commit; do \
    case "${name}" in '' | '#'*) continue ;; esac; \
    asdf plugin add "${name}" "${url}" \
      && git -C "${ASDF_DATA_DIR}/plugins/${name}" checkout --quiet "${commit}" \
      || exit 1; \
  done < /tmp/tool-versions/asdf-plugins

# Every tool .tool-versions pins, installed from that file. It is copied to a
# scratch directory and removed afterwards rather than left in the home
# directory, where asdf would treat it as a global fallback: a tool this
# repository does not pin should be missing in this container, not silently
# supplied.
COPY --chown=1000:1000 .tool-versions /tmp/tool-versions/.tool-versions
WORKDIR /tmp/tool-versions
RUN asdf install \
  && rm -rf /tmp/tool-versions

WORKDIR /workspace
