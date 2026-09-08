# github-template

[![License](https://img.shields.io/github/license/ivan-pinatti-labs/github-template?logo=Github&style=for-the-badge)](LICENSE.md)
[![GitHub issues](https://img.shields.io/github/issues-raw/ivan-pinatti-labs/github-template?logo=Github&style=for-the-badge)](https://github.com/ivan-pinatti-labs/github-template/issues)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/ivan-pinatti?logo=Github&style=for-the-badge)](https://github.com/sponsors/ivan-pinatti)
[![GitHub Repo stars](https://img.shields.io/github/stars/ivan-pinatti-labs/github-template?logo=Github&style=for-the-badge)](https://github.com/ivan-pinatti-labs/github-template)
[![GitHub forks](https://img.shields.io/github/forks/ivan-pinatti-labs/github-template?logo=Github&style=for-the-badge)](https://github.com/ivan-pinatti-labs/github-template/forks)
[![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/ivan-pinatti-labs/github-template?utm_source=oss&utm_medium=github&utm_campaign=ivan-pinatti-labs%2Fgithub-template&labelColor=171717&color=FF570A&label=CodeRabbit+Reviews&style=for-the-badge)](https://coderabbit.ai)

A GitHub template repository: the starting point for a new project, with
pre-commit, dependency automation, review automation, the
`ivan-pinatti-labs` merge pipeline, and the usual community files already
wired up. Click **Use this template** to create a repository from it, then
follow [Using this template](#using-this-template) below.

## Requirements

- [`pre-commit`](https://pre-commit.com/#install) and `git`.
- **Docker** (or a Docker CLI compatible runtime) on `PATH`.
  `checklist-github-actions` in
  [.pre-commit-config.yaml](.pre-commit-config.yaml) lints
  `.github/workflows/*.yml` with `actionlint-docker`, which runs inside a
  container. This template ships GitHub Actions workflows, so that hook
  runs, and needs Docker, from the very first
  `pre-commit run --all-files`. Drop the `checklist-github-actions` id
  from [.pre-commit-config.yaml](.pre-commit-config.yaml) if you would
  rather not carry that requirement.
- **Python 3.10 or newer** on `PATH`. `checklist-github-actions` also runs
  `zizmor`, a GitHub Actions workflow security auditor, alongside
  `actionlint-docker`; `zizmor` needs that floor and installs into its own
  `pre-commit` environment through `additional_dependencies`, so no manual
  install step is required beyond having a new enough `python3` available.
  It runs with its offline audit set only, so no token is required.

## What you get

- **Pre-commit**, consuming the checklists published by
  [ivan-pinatti-labs/pre-commit-checklists](https://github.com/ivan-pinatti-labs/pre-commit-checklists)
  through a single `repo:` entry and a `rev:` pin: see
  [.pre-commit-config.yaml](.pre-commit-config.yaml).
- **PR validation**: a workflow that runs pre-commit on every pull request,
  posts the result as a PR comment, and applies labels from
  [.github/labeler.yml](.github/labeler.yml). It is a gate, not a fixer:
  any finding fails the job, and nothing is committed or pushed back to
  the PR branch. A pull request opened from a fork gets a read-only
  token, so the comment and the labels are skipped for it; pre-commit
  still runs and still gates the merge either way. See
  [.github/workflows/pull-request.yml](.github/workflows/pull-request.yml).
- **Auto tag and release**: every push to `main` (what a merged PR
  produces) computes the next version from Conventional Commit prefixes,
  tags it, and creates a GitHub release. See
  [.github/workflows/new-tag-and-release.yml](.github/workflows/new-tag-and-release.yml).
- **Renovate**, this template's active dependency bot: the asdf tool pins
  in `.tool-versions`, `.pre-commit-config.yaml`'s `rev:` pin, and every
  `.github/workflows/*.yml` action pin, one grouped pull request per
  ecosystem. See [.github/renovate.json5](.github/renovate.json5).
- **Dependabot**, present but disabled
  (`open-pull-requests-limit: 0`) for the same `pre-commit` and
  `github-actions` ecosystems Renovate already watches. It ships fully
  configured, not stripped down, so switching either ecosystem back to
  Dependabot instead of Renovate is a one-line change (that limit, back to
  `5`) rather than reconstructing config from scratch. See
  [.github/dependabot.yml](.github/dependabot.yml).
- **CodeRabbit**, reviewing pull requests once they leave draft state, plus
  the org's merge pipeline: `CodeRabbit Gate` publishes `Pin Only` and
  `Review Verified` as required status checks, `CodeRabbit Review Queue`
  nudges CodeRabbit into reviewing a dependency bot's pull request (which it
  never does unattended), and `Bot Auto Merge` supplies an approving review
  so a pin-only dependency bump or the repository owner's own pull request
  can enter the merge queue. See
  [.coderabbit.yaml](.coderabbit.yaml) and
  [docs/MERGE_PIPELINE.md](docs/MERGE_PIPELINE.md) for the full mechanics,
  including what branch protection, the merge queue ruleset, and two GitHub
  App installations expect from a repository created from this template.
- **Issue and pull request templates**, a stale-issue policy, a
  `CODEOWNERS` file, and a `FUNDING.yml`, all under
  [.github/](.github/).
- **Community files**: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md),
  [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
  [LICENSE.md](LICENSE.md) (Apache License 2.0), and
  [NOTICE.md](NOTICE.md).

## What this template deliberately does not include

This repository is meant to be generic and language-agnostic, so it does
not bake in any one project type's tooling: no language-specific linter
configuration, no build system, no test runner, no Renovate manager beyond
`asdf`, `github-actions` and `pre-commit`, and no `dependabot.yml`
ecosystem beyond `pre-commit` and `github-actions` (both present but
disabled; see "What you get" above). Once you know what the new project is
written in, add the pieces that fit it, for example a language-specific
pre-commit checklist id (`checklist-dev-python`, `checklist-dev-shell`, and
so on, see
[pre-commit-checklists' hook catalogue](https://github.com/ivan-pinatti-labs/pre-commit-checklists/blob/main/docs/hook-catalogue.md))
and a matching Renovate manager or Dependabot ecosystem block, whichever
bot you would rather run for it (see step 5 below).

## Using this template

This repository is a GitHub template repository (`is_template: true`):
the baseline for a new repo, with pre-commit, dependency automation,
review automation, and the usual community files already wired up.

1. Click **Use this template** at the top of this repository's GitHub
   page, and create your new repository.
2. Clone it, then put the starter README in place of this one, which
   describes the template rather than your project:

   ```shell
   mv docs/STARTER_README.md README.md
   ```

3. Find and replace the placeholders (search for `REPLACE_ME` across the
   tree to find them all). `REPLACE_ME_OWNER` is this new repository's own
   GitHub org or user (`REPLACE_ME_OWNER/REPLACE_ME_REPO_NAME` throughout);
   it is not the same value as `REPO_OWNER_LOGIN` in step 6 below, which can
   be a different account entirely:
   - `README.md`, the one you just moved into place: project name,
     description, and the repository owner and name throughout its badge
     row.
   - [CITATION.cff](CITATION.cff): project title, abstract, repository
     owner and URL, and keywords.
   - [llms.txt](llms.txt): project name, description, key files, tech
     stack, and the repository owner and name in the canonical
     repository line.
4. Update the `rev:` pin in [.pre-commit-config.yaml](.pre-commit-config.yaml)
   to the latest release tag of `pre-commit-checklists`, then run:

   ```shell
   pre-commit install
   pre-commit run --all-files
   ```

5. Add a language-specific pre-commit checklist id once you know what the
   project is written in, and decide which bot should watch its
   dependencies. Renovate is this template's active default; extend
   [.github/renovate.json5](.github/renovate.json5) to watch the new
   ecosystem too. As shipped, `enabledManagers` is an explicit list of
   exactly the three pin surfaces this template ships with (`asdf`,
   `github-actions`, `pre-commit`). Renovate has a
   [native manager](https://docs.renovatebot.com/modules/manager/) for most
   ecosystems (`npm`, `pip_requirements`, `bundler`, `gomod`,
   `dockerfile`, and so on): add its name to `enabledManagers` and Renovate
   picks up the matching manifest with no further configuration. For an
   ecosystem Renovate has no native manager for, widen `enabledManagers` to
   include `regex` instead and add a
   [custom manager](https://docs.renovatebot.com/modules/manager/regex/)
   with a `matchStrings` pattern that finds the version string, the shape
   `ivan-pinatti-labs/rsync-crypt`'s copy of this file uses for its
   `.env.example` pin. Either way, add a matching `packageRules` entry
   grouping the new ecosystem's updates behind its own label, the same
   shape as the `asdf`, `github-actions` and `pre-commit` groups already
   there, so a single grouped pull request per ecosystem is preserved and
   `bot-auto-merge.yml`'s automerge grant does not start merging unrelated
   bumps together. Dropping `enabledManagers` entirely, to fall back to
   `config:recommended`'s own defaults, is the other option, once enough
   ecosystems are in play that maintaining an explicit list stops being
   worth it.

   Dependabot is the other option, for a new ecosystem or for either one
   this template already ships: [.github/dependabot.yml](.github/dependabot.yml)
   carries a commented `REPLACE_ME_ECOSYSTEM` block at the bottom to copy
   for a new ecosystem, and its existing `pre-commit` and `github-actions`
   blocks are already fully configured, just disabled
   (`open-pull-requests-limit: 0`). To run Dependabot instead of Renovate
   for either of those two, raise that block's `open-pull-requests-limit`
   back to `5` and drop the matching manager out of Renovate's
   `enabledManagers` at the same time: running both bots against the same
   ecosystem opens duplicate pull requests for the same bump.
6. Set up what the merge pipeline in
   [docs/MERGE_PIPELINE.md](docs/MERGE_PIPELINE.md) needs but does not ship
   as a file: a `REPO_OWNER_LOGIN` repository variable set to the account
   that opens this repository's owner pull requests, branch protection and
   the merge queue ruleset on `main` (only after this new repository's
   first pull request, the one that actually adds these workflows, has
   merged; see that document's "The bootstrap gap"), the new repository
   added to both the CodeRabbit and Renovate GitHub App installations'
   selected-repository lists, and the `CODERABBIT_NUDGE_TOKEN` org secret's
   visibility extended to it. Neither bot needs a schedule picked for it:
   both run daily in every repository, and a pin-only bump from either
   consumes no CodeRabbit review quota. See
   [ivan-pinatti-labs/.github](https://github.com/ivan-pinatti-labs/.github)
   under "Dependency policy".
7. Decide whether the default [LICENSE.md](LICENSE.md) (Apache License 2.0)
   is the right choice for the new project, and replace it if not.

## License

See [LICENSE.md](LICENSE.md) for full details.

## Contribute / Donate

If you use this template, entirely or partially, or get inspired by it,
consider buying me a coffee or a beer, I would really appreciate it:
[buymeacoffee.com/ivan.pinatti](https://www.buymeacoffee.com/ivan.pinatti).
