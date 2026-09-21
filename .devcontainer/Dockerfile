# Development container: everything this repository's hooks need, on top of
# the organization's shared base image. See .devcontainer/README.md for how to
# start it and why each run argument is there.
#
# The base image is pinned by digest. BASE_IMAGE is a build argument only so a
# change to the base image can be tested against this repository before it is
# published.
ARG BASE_IMAGE=ghcr.io/ivan-pinatti-labs/devcontainer-base@sha256:db75fbbf8972f6f1d7746c06238fbf15a387e224947e0e0dd5bf4d5fe3844d0b
FROM ${BASE_IMAGE}

USER 0:0

# Everything this repository needs, from signed package repositories.
#
# pre-commit comes from Ubuntu's own archive. gh comes from GitHub's, whose
# signing key the base image checks against a fingerprint and installs
# without enabling the repository, so the source entry below is what opts in
# to it. The base image's docs/TOOL_SOURCES.md has the source line for the
# other repositories it carries keys for (NodeSource and HashiCorp), and the
# reasoning behind all of this.
#
# A project created from this template adds what it needs here. Prefer a
# distribution package, then a vendor's own signed apt repository, then the
# tool's official container image. There is no version manager in this
# organization and nothing here pins a package version: Ubuntu and these
# vendors ship security fixes by moving a version inside a release, so a pin
# would hold this container on the superseded build until somebody edited it
# by hand.
#
# That makes this layer deliberately rolling, not reproducible. The digest
# above fixes what this builds on and says nothing about what apt resolves on
# top, so two builds weeks apart can and should install different package
# builds. Reproducing an exact container means keeping the image, not
# re-running this file.
# hadolint ignore=DL3008
RUN printf '%s\n' \
      'deb [arch=amd64 signed-by=/usr/share/keyrings/github-cli.gpg] https://cli.github.com/packages stable main' \
      > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    gh \
    pre-commit \
  && rm -rf /var/lib/apt/lists/*

USER 1000:1000

WORKDIR /workspace
