# REPLACE_ME_PROJECT_NAME

![GitHub issues](https://img.shields.io/github/issues-raw/ivan-pinatti/REPLACE_ME_REPO_NAME?logo=Github&style=for-the-badge)
![GitHub Sponsors](https://img.shields.io/github/sponsors/ivan-pinatti?logo=Github&style=for-the-badge)

REPLACE_ME_PROJECT_DESCRIPTION

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
- **Dependabot**, watching `.pre-commit-config.yaml` and every
  `.github/workflows/*.yml` action pin. See
  [.github/dependabot.yml](.github/dependabot.yml).
- **Renovate**, scoped to the asdf tool pins in `.tool-versions`, the one
  pin surface Dependabot cannot read. See
  [.github/renovate.json5](.github/renovate.json5).
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
configuration, no build system, no test runner, no `dependabot.yml`
ecosystem beyond `pre-commit` and `github-actions`. Once you know what
the new project is written in, add the pieces that fit it, for example a
language-specific pre-commit checklist id (`checklist-dev-python`,
`checklist-dev-shell`, and so on, see
[pre-commit-checklists' hook catalogue](https://github.com/ivan-pinatti-labs/pre-commit-checklists/blob/main/docs/hook-catalogue.md))
and a matching Dependabot ecosystem block.

## Using this template

This repository is a GitHub template repository (`is_template: true`):
the baseline for a new repo, with pre-commit, dependency automation,
review automation, and the usual community files already wired up.

1. Click **Use this template** at the top of this repository's GitHub
   page, and create your new repository.
2. Clone it, then find and replace the placeholders below (search for
   `REPLACE_ME` across the tree to find them all):
   - [CITATION.cff](CITATION.cff): project title, abstract, repository
     URL, and keywords.
   - [llms.txt](llms.txt): project name, description, key files, and tech
     stack.
   - This README: project name, description, and the repository name
     inside the issues badge above and the license badge further down.
3. Update the `rev:` pin in [.pre-commit-config.yaml](.pre-commit-config.yaml)
   to the latest release tag of `pre-commit-checklists`, then run:

   ```shell
   pre-commit install
   pre-commit run --all-files
   ```

4. Add a language-specific pre-commit checklist id, and a matching
   Dependabot ecosystem in [.github/dependabot.yml](.github/dependabot.yml),
   once you know what the project is written in. Widen, or drop, the
   `enabledManagers` restriction in
   [.github/renovate.json5](.github/renovate.json5) at the same time:
   as shipped it is scoped to the asdf tool pins in `.tool-versions`
   only, on the assumption that Dependabot already owns everything else
   this template ships with.
5. Set up what the merge pipeline in
   [docs/MERGE_PIPELINE.md](docs/MERGE_PIPELINE.md) needs but does not ship
   as a file: a `REPO_OWNER_LOGIN` repository variable set to the account
   that opens this repository's owner pull requests, branch protection and
   the merge queue ruleset on `main` (only after this new repository's
   first pull request, the one that actually adds these workflows, has
   merged; see that document's "The bootstrap gap"), the new repository
   added to both the CodeRabbit and Renovate GitHub App installations'
   selected-repository lists, the `CODERABBIT_NUDGE_TOKEN` org secret's
   visibility extended to it, and a `.github/dependabot.yml` /
   `.github/renovate.json5` schedule that does not collide with a sibling
   repository's (see `ivan-pinatti-labs/.github`'s `docs/BOT_SCHEDULE.md`).
6. Decide whether the default [LICENSE.md](LICENSE.md) (Apache License 2.0)
   is the right choice for the new project, and replace it if not.
7. Delete this section, and the section above it, once the new project has
   its own README content to replace them with.

## License

[![license](https://img.shields.io/github/license/ivan-pinatti/REPLACE_ME_REPO_NAME?style=plastic)](LICENSE.md)

See [LICENSE.md](LICENSE.md) for full details.

## Contribute / Donate

If you use this template, entirely or partially, or get inspired by it,
consider buying me a coffee or a beer, I would really appreciate it:
[buymeacoffee.com/ivan.pinatti](https://www.buymeacoffee.com/ivan.pinatti).
