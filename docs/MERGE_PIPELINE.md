# The Merge Pipeline

<!-- cspell:words coderabbit coderabbitai -->

What happens between opening a pull request against this repository and it
landing on `main`. Ported from `ivan-pinatti-labs/rsync-crypt`'s document of
the same name, trimmed to what this repository actually has: no app code, no
build, no test suite, and no Dockerfile, so there is no `Tests` context and
no `Docker Build` job here, unlike that repository. Where the reasoning is
identical it is only summarized, not restated; see rsync-crypt's
`docs/MERGE_PIPELINE.md` for the fuller version this one was trimmed from,
and `ivan-pinatti-labs/.github`'s `docs/MERGE_PIPELINE.md` for a smaller
worked example of the same kind of trim, for a repository with no merge
queue and no `Pin Only` at all. This repository sits between the two: it has
no app code like `.github`, but it does have a merge queue and a
dependency-bot fast lane, like rsync-crypt, so it carries `Pin Only` and
`bot-auto-merge.yml`'s full owner-approval and bot-approval mechanics that
`.github`'s copy does not need.

This repository is also a GitHub template (`is_template: true`): every file
this document describes ships to a repository created from it. What does
and does not follow automatically is called out at the end, in "Using this
pipeline from a repository created from this template."

## Every required status context

| Context | What it actually proves | Who publishes it |
| --- | --- | --- |
| `Pre-commit` | The full pre-commit hook set passed over every file | `pull-request.yml`, as a job |
| `Pin Only` | A dependency bot's diff changes nothing but a version in a pin position; `success` with a "not a dependency bot pull request" description on everything else | `coderabbit-gate.yml`, published directly onto the head SHA |
| `Review Verified` | CodeRabbit's actual review outcome, not merely that it reported something | `coderabbit-gate.yml`, published directly onto the head SHA |

`Pre-commit` is an ordinary workflow job: GitHub reports a job's own pass or
fail as the check. The other two are commit statuses, written directly by a
workflow step rather than read off a job's outcome, for the same reason as
in rsync-crypt: a status a workflow chooses whether to write, and what to
write, does not read as passed merely because it was skipped.

There is no `Tests` context and no `Docker Build` job: this repository has
no app code to run tests against and nothing to build a container image
from. Every place rsync-crypt's document reasons about those two, this one
simply drops.

## A human pull request

Open it as a **draft** first. `Pre-commit` runs the full hook set over every
file, and CodeRabbit does not review a draft at all: `.coderabbit.yaml` sets
`drafts: false` on purpose, so a review is not spent on a diff the
mechanical linters have not finished cleaning up yet.

**Mark it ready for review** once `Pre-commit` is green. That is what starts
CodeRabbit. Address what it raises, pushing fixes as needed; each push
re-runs the job and gets a fresh review.

Once every required check reads green and a maintainer has approved it, the
pull request is eligible for the merge queue, but entering it still needs
someone to select **Merge when ready** (or enable auto-merge); nothing here
enqueues it on its own. Once enqueued, it merges when the queue's own run of
the same check set passes on the commit the queue actually builds; see "The
merge queue" below.

## The repository owner's own pull request

The owner is the only account with write access, and GitHub refuses to let
an account approve its own pull request, which would otherwise be a genuine
deadlock once the queue is live: `gh pr merge --admin` skips the queue
entirely, and arming auto-merge on an unapproved pull request leaves it
enqueued forever with no `merge_group` run, because `enforce_admins: false`
exempts the owner from performing a merge without approval, not from the
approval the queue itself requires to accept the pull request at all. Both
failure modes were confirmed empirically on `ivan-pinatti-labs/rsync-crypt`,
not assumed.

`bot-auto-merge.yml`'s `approve-owner` job is the fix: once `Pre-commit`,
`Pin Only` and `Review Verified` are all green, it supplies the approval
that makes the pull request queue eligible. It does not arm auto-merge,
deliberately: the owner still decides when to enqueue, which is the "check
everything is fine, then merge" step the rest of this pipeline takes away
from nobody else. This approval is not evidence a human read the diff; it
is issued the moment the three contexts settle, with no review of their
content, which is exactly why it waits for `Review Verified` rather than
for `Pin Only` alone. `Review Verified` is what actually carries "a review
happened," and nothing else in this pipeline does. A contributor or a fork
gets no approval from this job and still needs a genuine human review, same
as always.

`Review Verified` is realistically the slowest of the three contexts to
settle, since it waits on CodeRabbit's own review, which is why this job
also reacts to `coderabbit-gate.yml` finishing a run (a `workflow_run`
trigger, not `pull_request_target` alone), re-checking every open
owner-authored pull request each time rather than only the one that
happened to prompt it. See rsync-crypt's fuller document for why it is
`workflow_run` and not a `status` trigger on `Review Verified` itself
(`GITHUB_TOKEN` publishes that status, and GitHub does not start new
workflow runs from events a `GITHUB_TOKEN` creates).

## A dependency bot pull request

Dependabot and Renovate open pull requests unattended. For the ones that are
pin only:

1. **`Pin Only` is graded.** `scripts/assert-pin-only-diff.py` checks that
   every changed line differs from its counterpart in nothing but a
   version, in a pin position, across three allowed pin surfaces
   (`.tool-versions`, `.pre-commit-config.yaml`, `.github/workflows/`), and
   `coderabbit-gate.yml` publishes its verdict as the `Pin Only` status. A
   number that is not a pin does not count as one.
2. **The approval is supplied, conditionally.** `bot-auto-merge.yml` waits
   for `Pin Only` to read `success` and then supplies the approving review
   branch protection requires. A diff that is not pin-only gets no approval
   and waits for a person, same as a major bump does.
3. **GitHub enqueues and merges it** once every required check, including
   `Review Verified`, is green and the approval is in place, the same as
   any other pull request.

`scripts/coderabbit-review-verdict.py`'s bot lane resolves `Review Verified`
straight to `success` with the description "pin-only diff, nothing to
review" the moment `Pin Only` reads `success`, and CodeRabbit is never asked
for an opinion; see rsync-crypt's document, "What actually gets reviewed,
and what does not," for the fuller reasoning, unchanged here. Renovate's
`minimumReleaseAge: "7 days"` in `.github/renovate.json5` is this
repository's own copy of the actual defence against a release that is well
formed and malicious: `Pin Only` can tell a line changed nothing but a
version, but it cannot tell a good release from a backdoored one.

## `Review Verified`, and the bug it exists to fix

Ported unchanged in reasoning from rsync-crypt, itself ported from
`docker-torrent-box-with-vpn`: a green `CodeRabbit` check does not mean a
review happened, because CodeRabbit posts through the legacy commit status
API, which offers only `error`, `failure`, `pending` and `success`, with no
fifth state for "green, but not for the reason you think." An exhausted
review quota, a skipped draft, and an actual completed review all read
`success`. Three pull requests merged with no review having actually
happened on `docker-torrent-box-with-vpn` as a direct result (its #114).

`scripts/coderabbit-review-verdict.py`, published as `Review Verified` by
`coderabbit-gate.yml`, is the fix: it reads the actual description behind
the `CodeRabbit` status rather than its color, and grades in three lanes (a
draft is `pending`; a clean pin-only bot pull request is `success` with no
review at all; everything else is `success` only for the literal
description `Review completed`, `pending` while a review is queued or
running, and `failure` otherwise). See the script's own docstring for the
full reasoning behind each lane; it is the authoritative version, not this
document.

## Recovering a stuck `Review Verified`

`coderabbit-gate.yml`'s hourly schedule (`53 * * * *`, offset from
`coderabbit-review-queue.yml`'s `29 * * * *` and from
`ivan-pinatti-labs/rsync-crypt`'s and `ivan-pinatti-labs/.github`'s own `47 * * * *`
sweeps) is a real mitigation, not a guarantee: GitHub's own documentation
says scheduled workflows on public repositories are deprioritized under
load and can be skipped outright rather than merely delayed, and
rsync-crypt has already seen it happen twice in a row against its own
schedule. `workflow_dispatch` on `coderabbit-gate.yml` is the manual
recovery path, run by anyone with write access, either against a single
`pr_number` or, left blank, against every open pull request at once. See
rsync-crypt's fuller document, "Recovering a stuck `Review Verified`,
honestly," for the full reasoning; it applies here unchanged.

`coderabbit-review-queue.yml`'s hourly nudge (`29 * * * *`) is what actually
gets CodeRabbit to look at a bot's pull request in the first place, since
CodeRabbit never reviews one on its own; see rsync-crypt's `CLAUDE.md`,
"CodeRabbit silently ignores `@coderabbitai review` from a bot account," for
why that comment has to come from a human account, or from
`CODERABBIT_NUDGE_TOKEN` rather than the default `GITHUB_TOKEN`, and for
what to check before assuming a nudge is in flight.

## The merge queue

Branch protection on `main` requires `Pre-commit`, `Pin Only` and
`Review Verified`, one approval, dismissal of stale reviews, approval of the
last push, conversation resolution and a linear history. `enforce_admins`
is `false`, which matters for exactly one account: it lets the owner merge
without being blocked by rules an admin can bypass, but it does not exempt
the owner's own pull request from the approval the queue itself requires to
accept it, which is what makes "The repository owner's own pull request"
above necessary. `allow_auto_merge` has to be enabled, or the queue cannot
accept anything at all.

The merge queue ruleset carries no bypass actor, deliberately: `merge_group`
triggers on `pull-request.yml` and `coderabbit-gate.yml` exist so that every
required context runs a second time against the queue's own temporary
commit before anything actually merges, and a bypass actor would let a
pull request skip that second run entirely.

## The bootstrap gap this pipeline was ported through

`coderabbit-gate.yml` and `bot-auto-merge.yml` both trigger on
`pull_request_target`, which runs the workflow file from the **base**
branch, not the pull request's own branch. On the pull request that first
adds these files to a repository's `main`, they do not exist on the base
branch yet, so neither one runs and `Pin Only` / `Review Verified` cannot be
published on that pull request. Branch protection cannot require either
context on that pull request either, for the same reason. This is the same
bootstrap rsync-crypt's own document describes ("ported ahead of need...
every job below was inert"), and it recurs every time this pipeline is
carried into a new repository, this one's own port PR included. Once that
one pull request merges, every later pull request runs against the version
of these files already on `main`, and the bootstrap gap closes for good.

## Using this pipeline from a repository created from this template

Every file this document describes is part of the template and ships to a
repository created from it. Five pieces of setup do not transfer
automatically. The first four are repository or organization settings; none
of them are files, so template creation has nothing to copy. The fifth is a
copied bot schedule whose slot must be reassigned to avoid collisions:

- **`REPO_OWNER_LOGIN`.** A repository variable, read by
  `bot-auto-merge.yml`'s `resolve-owner` job. This repository's own copy is
  set to `ivan-pinatti`, the personal account that opens pull requests here
  even though the repository itself lives under the `ivan-pinatti-labs`
  organization. A repository created from this template needs its own copy
  set to whichever account actually opens its owner's pull requests, or
  `resolve-owner` fails loudly (by design, rather than silently approving
  nothing) the first time it runs. This is a repository variable, not a
  file, so it is separate from the `REPLACE_ME_OWNER` text placeholder
  replaced in the README's "Using this template" step 2 (badges,
  `CITATION.cff`, `llms.txt`): that placeholder is this repository's own
  GitHub org or user, which is not necessarily the same account as the one
  set here.
- **Branch protection and the merge queue ruleset.** Apply both by hand to
  the new repository's `main`, the same shape described in "The merge
  queue" above, only after the port equivalent of this repository's own
  first pull request has merged (see "The bootstrap gap" above; it applies
  again, in full, to a brand-new repository).
- **`CODERABBIT_NUDGE_TOKEN`.** An org secret, scoped to a selected list of
  repositories rather than granted org-wide. A new repository needs adding
  to that list before `coderabbit-review-queue.yml` can post as anything
  other than a silently-failing `gh` call.
- **The CodeRabbit and Renovate GitHub App installations.** Both are
  installed on the `ivan-pinatti-labs` organization with
  `repository_selection: selected`. A new repository needs adding to both
  installations' repository lists before either app does anything on it at
  all; until then, `CodeRabbit` posts no status and Renovate opens nothing.
- **A `.github/dependabot.yml` slot that does not collide with a sibling
  repository's.** This repository's own slot (Saturday 06:00 and 06:30) is
  recorded in `ivan-pinatti-labs/.github`'s `docs/BOT_SCHEDULE.md`, together
  with every other repository's. A repository created from this template
  inherits Saturday verbatim; if it stays active alongside this one, pick a
  free hour, check it against every row of that table rather than against a
  day at a glance, and record the choice there.

  Only Dependabot needs a slot. `.github/renovate.json5` runs daily in every
  repository and is deliberately not day-scoped, because a Renovate pin-only
  bump resolves `Review Verified` through the bot lane without consuming a
  CodeRabbit review, so it does not compete for the quota that table exists
  to protect. Leave it daily rather than giving it a day of its own.

---

See also: [README.md](../README.md)
