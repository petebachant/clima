# Ownership and review

In the multi-repo setup, the repository boundary *is* the ownership boundary.
Whoever has merge rights on ClimaCore.jl decides what goes into ClimaCore.
In one repository that boundary has to be stated explicitly, and GitHub's
tool for that is [CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
plus a branch ruleset that requires code-owner review.

## How it works here

1. **One source of truth.** Each entry in [packages.toml](../packages.toml)
   has an `owners` list, and `[_repo]` lists the owners of shared
   infrastructure.
2. **Generated files.** `julia tools/mono.jl codeowners` writes
   [.github/CODEOWNERS](../.github/CODEOWNERS), the triage map, and the
   issue form (see [Team boards](#team-boards-github-projects)). CI fails
   if any of them is out of date. Don't edit them by hand.
3. **Who owns what:**
   - `packages/<Pkg>/` belongs to that package's owners.
   - `docs/dev/` belongs to the DeveloperGuides owners.
   - `examples/<name>/` and `experiments/<name>/` belong to the owners of
     their top-level in-repo packages, i.e. the ones no other in-repo dep in
     that environment depends on. `examples/atmos-single-column` is owned by
     the ClimaAtmos and ClimaAnalysis owners.
   - `tools/`, `.github/`, `.buildkite/`, `packages.toml`, `Project.toml`,
     and anything unmatched belong to `[_repo]` (`@CliMA/software`).
4. **Review requests and labels.** GitHub automatically requests review
   from the owners of every path a PR touches. Triage adds `pkg: <Pkg>`
   labels, so people can filter PRs and notifications by package, and puts
   the PR on the owning teams' boards.
5. **Enforcement.** Enable it with a ruleset on `main`:
   - require a pull request;
   - **require review from Code Owners**;
   - dismiss stale approvals on new pushes;
   - require the CI `plan`, `test`, and `examples` checks.

   One approval from *any* listed owner satisfies each matching rule.
   Owners must have write access, or GitHub ignores them.

## Cross-cutting PRs

A PR that changes ClimaCore and adapts ClimaAtmos needs one approval from
each set of owners. That's the same people who review today, but on one PR
with one CI run, instead of two PRs, a release, and a CompatHelper bump in
between. Conventions:

- **Commit order.** Put the upstream change and the downstream adaptations
  in separate commits, upstream first, so each owner can review "their"
  commit.
- **Who judges what.** Upstream owners judge the API change; downstream
  owners judge the adaptation. Neither re-reviews the other's part.
- **Say what's breaking.** If it's breaking, the PR description names the
  bumped package and the dependents released with it
  (`mono.jl bump … --release-dependents`).

**Mechanical sweeps** are PRs like "rename X across 10 packages", CI
updates, or formatter bumps. Requiring 10 owner approvals for them is
friction without value. GitHub rulesets can only exempt *actors*, not
labels. So:
- add `@CliMA/software` as a ruleset bypass actor;
- require that sweeps carry the `mechanical` label and get one owner
  approval from the most-affected package;
- audit them by label.

Keep the bypass list small.

## What the review data says

These are the owners proposed in `packages.toml`. They were derived from
merged PRs in each standalone repo from 2025-09-28 to 2026-09-28: reviewers
with ≥15% of a package's reviewed PRs, plus top authors, 2–3 per package.
**They are a starting point for each team to confirm, not a decision.**

| Package | Merged PRs/yr | Top reviewer's share | Proposed owners |
|:--|--:|--:|:--|
| ClimaAtmos | 511 | 47% | szy21, tapios |
| ClimaCoupler | 405 | 37% | szy21, juliasloan25 |
| ClimaLand | 239 | 44% | kmdeck, ph-kev |
| ClimaCore | 147 | 36% | imreddyTeja, dennisYatunin, ph-kev |
| CloudMicrophysics | 79 | 49% | trontrytel, haakon-e, tapios |
| ClimaCalibrate | 63 | **71%** | nefrathenrici, ph-kev |
| ClimaParams | 56 | 36% | szy21, trontrytel, nefrathenrici |
| Thermodynamics | 46 | 46% | szy21, tapios |
| SurfaceFluxes | 46 | 24% | akshaysridhar, tapios, szy21 |
| ClimaTimeSteppers | 45 | 24% | tapios, dennisYatunin, ph-kev |
| ClimaAnalysis | 43 | 58% | imreddyTeja, nefrathenrici, ph-kev |
| ClimaUtilities | 38 | 39% | ph-kev, imreddyTeja, nefrathenrici |
| ClimaDiagnostics | 34 | 41% | imreddyTeja, ph-kev, nefrathenrici |
| RRTMGP | 32 | 44% | szy21, tapios |
| Insolation | 20 | 35% | tapios, ph-kev, szy21 |
| ClimaComms | 17 | 35% | nefrathenrici, imreddyTeja, haakon-e |
| RootSolvers | 17 | 18% | imreddyTeja, tapios |
| ClimaInterpolations | 8 | 25% | giordano, ph-kev, imreddyTeja |
| DeveloperGuides | 12 | 17% | imreddyTeja, tapios |

Three things stand out.

**Review load is concentrated.** One person reviewed 487 PRs across these
repos in a year (about two per working day), spanning 8 packages. The next
two did 244 and 205. Required code-owner review on top of that would make
one person the bottleneck for most of the atmosphere stack.

The fix is to own paths with **teams, not individuals**. Then turn on the
team's [code review assignment](https://docs.github.com/en/organizations/organizing-members-into-teams/managing-code-review-settings-for-your-team)
(round robin or load balance), which spreads requests across members. This
is a real improvement over today: nothing currently spreads review load at
all.

**Bus factor.** ClimaCalibrate (71%), ClimaAnalysis (58%), CloudMicrophysics
(49%), and ClimaAtmos (47%) each rely mostly on one reviewer. Make sure
every path has at least two active owners; `mono.jl codeowners` already
refuses to write a rule with none.

**Low-traffic packages are the ones nobody watches.** ClimaInterpolations
(8 PRs/yr), ClimaComms, and RootSolvers (17 each) are at the bottom of the
dependency graph. A change there reaches everything above them, so they
need named owners most. In the monorepo, affected-package CI at least
tests every dependent on each change.

## Suggested teams

The existing org teams are organized by role (`software`, `land`, the broad
`atmosphereprocesses` and `clima-code-reviewers`), not by package. A
package-shaped set would be:

| Team | Packages |
|:--|:--|
| `@CliMA/core` | ClimaComms, ClimaCore, ClimaTimeSteppers, ClimaUtilities, ClimaDiagnostics, ClimaInterpolations, RootSolvers, ClimaAnalysis |
| `@CliMA/physics` | Thermodynamics, CloudMicrophysics, SurfaceFluxes, RRTMGP, Insolation, ClimaParams |
| `@CliMA/atmos` | ClimaAtmos |
| `@CliMA/land` (exists) | ClimaLand |
| `@CliMA/coupler` | ClimaCoupler, `experiments/` |
| `@CliMA/calibration` | ClimaCalibrate |
| `@CliMA/software` (exists) | infrastructure, `docs/dev/` |

A person can be on several teams. Once the teams exist, replace handles in
`packages.toml` with team names and rerun `mono.jl codeowners`.

## Team boards (GitHub Projects)

Each team gets one org-level GitHub Project, used as its kanban board.
Issues and PRs land on the right board automatically.

**Package → team.** In `packages.toml`, every package has a `team`, and
`[_teams]` maps each team to its project number. `mono.jl codeowners`
generates two things from that:
- [.github/triage.json](../.github/triage.json): the label → team → project
  map, plus the path prefixes for each label;
- [.github/ISSUE_TEMPLATE/issue.yml](../.github/ISSUE_TEMPLATE/issue.yml):
  an issue form with a required **Package** dropdown. Blank issues are
  disabled.

**[triage.yml](../.github/workflows/triage.yml) does the rest:**
- **Issues:** it applies the label chosen in the form.
- **PRs:** it applies one `pkg:` label per area the changed files touch
  (examples, experiments, infrastructure, dev guides, or a package).
- **Routing:** it adds the item to every matching team's board. Adding is
  idempotent. A PR touching ClimaCore and ClimaAtmos lands on both the
  `core` and `atmos` boards, which is how both teams see a cross-cutting
  change.
- **Relabeling:** relabeling an issue by hand re-runs triage, so moving an
  issue to another package also puts it on that team's board.

Labeling and routing happen in the same job on purpose. Labels added with
`GITHUB_TOKEN` don't trigger other workflows, so the usual pattern (a
labeler workflow plus a separate "add to project on label" workflow) would
never fire for bot-applied labels.

**Setup (org admin):**
1. Create one project per team. Use the same template for each (e.g.
   Status: Triage → Ready → In progress → Review → Done; plus fields for
   Package and Priority), then put the numbers in `packages.toml`
   `[_teams]`.
2. Add a `PROJECTS_TOKEN` secret: a GitHub App or fine-grained PAT with
   org Projects read/write. Without it, triage only labels.
3. In each project, turn on the built-in workflows: "Item closed → Done",
   "Pull request merged → Done", and "Auto-archive items" after N days.
   Leave "Auto-add to project" off. triage.yml does the adding, with one
   rule set for all teams instead of per-project filters.
4. Optionally, one **cross-team roadmap** project that pulls in items
   labeled `breaking` or `release`, so coordinated releases are visible
   across teams.

Teams map roughly 1:1 onto CODEOWNERS groups. The owners who review a path
also triage its board.

## Also worth setting up

- **A pointer for users.** The CODEOWNERS file doubles as "who to ask about
  X". Link it from the README once owners are confirmed.
