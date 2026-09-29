# CliMA monorepo (prototype)

The core CliMA Julia packages in one repository, so a change that spans
packages lands in one PR and is tested against everything downstream of it
before anyone releases.

> [!NOTE]
> **This is an evaluation.** The standalone repos are still the source of
> truth and are synced in weekly (`tools/subtree.sh pull`). The questions
> being answered, and how, are in [EVALUATION.md](EVALUATION.md).

Every package stays a separate registered Julia package with its own
version, `Project.toml`, and `[compat]`. Only the repository is shared.

```text
packages/<Pkg>/     one directory per package (a git subtree of CliMA/<Pkg>.jl)
examples/           small cross-package recipes, run in CI (start here as a user)
experiments/        the org's flagship scheduled simulations (AMIP, long runs; proposal)
docs/dev/           DeveloperGuides: shared engineering standards
docs/PLAN.md        plan for one consolidated docs site
docs/OWNERSHIP.md   CODEOWNERS, team boards, review policy
tools/mono.jl       graph, affected, compat, test, bump, releases, workspace, codeowners
tools/subtree.sh    import/sync packages from their standalone repos
tools/register.sh   registers bumped packages, upstream first
packages.toml       what's in the repo and where it comes from
Project.toml        Julia workspace (generated; lists every package + test env)
```

Packages: ClimaComms, ClimaParams, RootSolvers, ClimaInterpolations,
Insolation, ClimaAnalysis, Thermodynamics, SurfaceFluxes, CloudMicrophysics,
RRTMGP, ClimaCore, ClimaTimeSteppers, ClimaUtilities, ClimaDiagnostics,
ClimaAtmos, ClimaLand, ClimaCoupler, ClimaCalibrate. Oceananigans, ClimaOcean,
ClimaSeaIce and EnsembleKalmanProcesses stay out on purpose: they have
large communities of their own.

## Examples

If you want to *use* CliMA, start with [examples/](examples/). Each one is a
short, tested script for a common task:

- [CliMA physics in your own model](examples/physics-in-your-model/)
- [ClimaAtmos single-column simulation](examples/atmos-single-column/)
- [Single-column soil simulation](examples/land-single-site/)
- [Build your own model on ClimaCore](examples/build-on-climacore/)
- [Calibrate a toy model](examples/calibrate-toy-model/)
- [Coupled slabplanet](examples/coupled-slabplanet/) (nightly)

## Setup

Requires Julia 1.12+ for day-to-day work (workspaces). 1.10 LTS is still
tested; see [LTS](#julia-110-lts).

```bash
git clone https://github.com/CliMA/clima && cd clima
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

This resolves **one** `Manifest.toml` for every package and test
environment. Every in-repo package is tracked by path, so
`using ClimaCore` anywhere in the repo means *this checkout* of ClimaCore.
There's no `Pkg.develop` step to remember or undo.

## Common tasks

| I want to… | Run |
|:--|:--|
| Work on a package in the REPL | `julia --project=packages/ClimaAtmos` |
| Run a package's tests | `julia --project=packages/ClimaAtmos -e 'using Pkg; Pkg.test()'` |
| Run one test file | `julia --project=packages/Thermodynamics/test packages/Thermodynamics/test/<file>.jl` ¹ |
| See what my change affects | `julia tools/mono.jl affected main` |
| See the package graph | `julia tools/mono.jl graph` |
| Check compat bounds are consistent | `julia tools/mono.jl compat` |
| Test against *registered* deps (what users get) | `julia tools/mono.jl test ClimaAtmos --registered` |
| Test on Julia 1.10 | `julia +1.10 tools/mono.jl test ClimaAtmos` |
| Release a package | bump `version` in its `Project.toml` in your PR (see below) |
| Make a breaking release | `julia tools/mono.jl bump ClimaCore minor --release-dependents` |
| Run an example | `julia --project=examples/<name> examples/<name>/run.jl` |
| Format and lint before committing | `prek install` once; hooks run on `git commit` |
| Update CODEOWNERS / triage after editing `packages.toml` | `julia tools/mono.jl codeowners` |
| Use this repo's HEAD from another project | see [Using unreleased code elsewhere](#using-unreleased-code-elsewhere) |

¹ Only packages with a `test/Project.toml` have their test env in the
workspace. Packages using `[extras]`/`[targets]` run through `Pkg.test()`.

### Making a change that spans packages

Just make it. Edit `packages/ClimaCore/src/...` and
`packages/ClimaAtmos/src/...` on one branch and open one PR. CI runs
`mono.jl affected` against the base branch and tests every changed package
**and everything downstream of it**, all against the in-repo HEADs.

If the ClimaCore change is breaking, the PR should also:

1. Bump ClimaCore's version (`mono.jl bump ClimaCore minor`). This widens
   `[compat]` in every in-repo dependent, including test environments.
2. Fix the dependents in the same PR. That's the point of the monorepo.
3. Decide whether dependents need a release. Widened compat only reaches
   users once the dependent is released, so `--release-dependents`
   patch-bumps each one.

CI's first job runs `mono.jl compat --strict`, which fails when any
dependent's `[compat]` (or test env's) excludes the in-repo version of a
dependency. That's how "forgot to update downstream" is caught before merge
instead of after release.

### Releasing

A release is a reviewed PR that changes `version` in
`packages/<Pkg>/Project.toml`. On merge, [register.yml](.github/workflows/register.yml)
comments `@JuliaRegistrator register subdir=packages/<Pkg>` on the merge
commit for each bumped package. It goes in dependency order, and each
dependent waits until its upstream's new version is in General. TagBot then
creates `<Pkg>-v<version>` tags and GitHub releases.

To preview what a merge would register:

```bash
tools/register.sh main --dry-run
```

Update `NEWS.md` in the package you bumped, as before.

### Julia 1.10 (LTS)

1.10 has no workspaces. `tools/mono.jl test <Pkg>` builds a temporary
environment, devs the package plus all of its in-repo upstream deps by path,
and runs its tests. CI runs every affected package on both 1.12 and LTS.

### Using unreleased code elsewhere

From a project outside this repo (Julia 1.11+):

```toml
# your Project.toml
[sources]
ClimaCore = {url = "https://github.com/CliMA/clima", subdir = "packages/ClimaCore", rev = "main"}
```

or `Pkg.add(url="https://github.com/CliMA/clima", subdir="packages/ClimaCore", rev="my-branch")`.

### GPU and MPI

GitHub Actions is CPU-only. [.buildkite/pipeline.yml](.buildkite/pipeline.yml)
calls `mono.jl buildkite`, which emits CPU, GPU (`CLIMACOMMS_DEVICE=CUDA`), and
MPI (`CLIMACOMMS_CONTEXT=MPI`) steps for the affected packages only.
Package-specific Buildkite pipelines (ClimaAtmos's configs, ClimaCoupler's
AMIP runs, …) still live under `packages/<Pkg>/.buildkite/` and are not yet
wired in.

### Formatting

One style for the whole repo, adopted from ClimaAtmos:
[.JuliaFormatter.toml](.JuliaFormatter.toml) and
[.pre-commit-config.yaml](.pre-commit-config.yaml), with JuliaFormatter
pinned in `.dev/format`. Run `prek install` once; CI runs the same hooks.
While `packages/*` are synced from upstream, they keep their own formatter
configs, and ClimaAtmos's and ClimaCore's own hooks run through prek's
nested-config support. The one-time whole-repo reformat happens at cutover.

### Ownership

`packages.toml` lists each package's `owners` and `team`. From those,
`mono.jl codeowners` generates CODEOWNERS (required reviews), the issue
form, and the triage map. A workflow uses them to label issues and PRs and
put them on each team's project board. See
[docs/OWNERSHIP.md](docs/OWNERSHIP.md).

### Adding a package

1. Add an entry to [packages.toml](packages.toml).
2. `tools/subtree.sh add <Pkg>`
3. Add `owners` and `team` to its entry, then run `julia tools/mono.jl workspace`
   and `julia tools/mono.jl codeowners` (CI checks both are up to date)
4. `julia --project=. -e 'using Pkg; Pkg.resolve()'`. If it doesn't resolve,
   the error names the stale bound.

### Syncing from upstream (evaluation period only)

```bash
tools/subtree.sh pull            # all
tools/subtree.sh pull ClimaCore  # one
```

A weekly workflow does this and opens a PR.

## Development standards

The shared CliMA developer guides live in [docs/dev/](docs/dev/), which is
the DeveloperGuides repo as a subtree. Start at
[docs/dev/AGENTS.md](docs/dev/AGENTS.md). Each package may also have its own
`AGENTS.md` and repo-specific guide.

## TODO

What's left, grouped by when it can happen. Details live in the linked
docs. Tick items off here as they land.

### Now (during the evaluation)

- [ ] **Get CI green on GitHub Actions.** The plan job is fixed; the test
  matrix, LTS, and examples jobs haven't run there yet. Watch for the cost
  of instantiating the 312-package workspace in every matrix job.
- [ ] **Upstream the `issubspace` fix.** Branch `fix/climacore-issubspace`
  → PRs to CliMA/ClimaCore.jl (methods + regression test) and
  CliMA/ClimaCoupler.jl (`output_writer`). Then unpin ClimaLand in the
  Coupler nightly. See [EVALUATION.md](EVALUATION.md#case-study-the-issubspace-outage-september-2026).
- [ ] **Report API/doc friction found by the examples**, e.g. the wrong
  SurfaceFluxes `config` keyword in the docs, `q_liq` vs `q_lcl` naming,
  ITime `≈` errors, ClimaLand default diagnostics writing to `.`. Details
  are in each example's agent report and in the commit messages.
- [ ] **Add an example: custom physics in ClimaAtmos + calibration**
  (user-defined boundary-layer closure, synthetic-observation calibration;
  cf. arXiv:2604.19500).
- [ ] **Run the trial** in [EVALUATION.md](EVALUATION.md#how-to-run-the-trial):
  2–3 real cross-cutting changes done here, and one low-traffic package
  (ClimaParams or RootSolvers) registered from here end to end.
- [ ] **Confirm owners and teams.** The `owners` in `packages.toml` are
  derived from review data. Create the `@CliMA/{core,physics,atmos,coupler,calibration}`
  teams and switch to team handles. See [docs/OWNERSHIP.md](docs/OWNERSHIP.md).
- [ ] **Create the team project boards** and the `PROJECTS_TOKEN` secret;
  fill in the project numbers in `packages.toml` `[_teams]`.
- [ ] **Turn on the branch ruleset** for `main`: code-owner review, required
  CI checks, `@CliMA/software` as the only bypass actor.
- [ ] **Resolve the AMIP experiment env** (`experiments/amip`) and load the
  coupled stack from it. The resolve was interrupted.
- [ ] **Standardize test environments** on `test/Project.toml` (7 packages
  still use `[extras]`/`[targets]`), so every test env joins the workspace.

### At cutover (once the monorepo is the source of truth)

- [ ] **One pre-commit config for every package.** Remove `packages/` and
  `docs/dev/` from the `exclude` in [.pre-commit-config.yaml](.pre-commit-config.yaml).
  Delete ClimaAtmos's and ClimaCore's nested `.pre-commit-config.yaml` and
  every `packages/*/.JuliaFormatter.toml`. Fix or `#! format: off` the 9
  files the pinned JuliaFormatter can't parse. Then run one
  `prek run --all-files` commit (423 files) and add it to
  `.git-blame-ignore-revs`.
- [ ] **Move registration here.** One General PR per package setting `repo`
  and `subdir`; enable [register.yml](.github/workflows/register.yml) and
  TagBot with an SSH key.
- [ ] **Stop the upstream sync**, archive the standalone repos with redirect
  READMEs, and delete `sync-upstream.yml`.
- [ ] **Delete per-package leftovers:** each `packages/*/docs/dev-guides`
  subtree, `update_dev_guides.yml`, and the per-package `.github/workflows`
  that are now inert (CI, TagBot, CompatHelper, formatter, downstream).
- [ ] **Consolidated docs site.** See [docs/PLAN.md](docs/PLAN.md#migration):
  store repo, `deploydocs` changes, MultiDocumenter aggregate.
- [ ] **Move the flagship simulations** into `experiments/`. See
  [experiments/README.md](experiments/README.md#migration-once-upstream-sync-stops);
  this deletes the `UPSTREAM_PACKAGES` machinery.
- [ ] **Port per-package Buildkite pipelines** (ClimaAtmos especially), or
  trigger them from the root pipeline.

### Decisions still open

- [ ] Merge internal-only packages (ClimaUtilities, ClimaDiagnostics,
  ClimaInterpolations) to remove reactive releases? See
  [EVALUATION.md](EVALUATION.md#question-3-less-release-maintenance).
- [ ] Commit the workspace `Manifest.toml`?
- [ ] Custom docs domain vs `clima.github.io/clima/`?
- [ ] Who owns `experiments/` and its cluster budget?
- [ ] Split the workspace (packages + tests vs examples/experiments) if
  shared resolution keeps coupling unrelated test deps?
