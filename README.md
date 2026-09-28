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
docs/dev/           DeveloperGuides: shared engineering standards
tools/mono.jl       graph, affected, compat, test, bump, releases, workspace
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

### Adding a package

1. Add an entry to [packages.toml](packages.toml).
2. `tools/subtree.sh add <Pkg>`
3. `julia tools/mono.jl workspace` (CI checks it's up to date)
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
