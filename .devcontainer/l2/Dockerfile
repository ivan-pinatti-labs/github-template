# This repository's L2 image: where its hooks, tests and package installs
# run, with the working tree and nothing else (no network, no credentials).
# `l2` builds it inside the L2 engine the first time it is needed, and again
# whenever this file changes. See docs/LAYERS.md in
# ivan-pinatti-labs/devcontainer-airlock.
#
# It starts from the shared L2 image, pinned by digest, which already carries
# pre-commit, Python, Node, Go and the linters this repository's hooks use.
# A project created from this template adds what its own hooks and tests
# need below. Prefer a distribution package, then a vendor's own signed apt
# repository (the base image carries the keys for GitHub, NodeSource and
# HashiCorp, enabled by a source line here), then the tool's official
# container image. Nothing pins a package version: the digest fixes what this
# builds on, and apt resolves the current security fixes on top.
ARG L2_IMAGE=ghcr.io/ivan-pinatti-labs/airlock-l2@sha256:fc340eb19b1c98dd346d4ef79c0f739668e464b40a0150ad704b6f5cb2069a43
# hadolint ignore=DL3006
FROM ${L2_IMAGE}
