# Experiments: the org's flagship simulations

`examples/` teaches one task in a few minutes on a laptop. `experiments/`
is different: the long, GPU-heavy simulations the org runs on a schedule to
track model quality and performance, such as the nightly AMIP, the weekly
long runs, and the SYPD benchmarks. Today they live inside
ClimaCoupler, ClimaAtmos, and ClimaLand, even though they exercise the
whole stack.

> [!NOTE]
> **Status: proposal plus one prototype** (`amip/`). The drivers and configs
> still live in `packages/*` because those directories are synced from
> upstream every week. Moving files out of them now would make every sync
> conflict. The move happens once the monorepo becomes the source of truth.

## What exists today

| Where | What | Cadence |
|:--|:--|:--|
| ClimaCoupler `experiments/AMIP`, `config/nightly_configs` | Coarse AMIP, 3 atmos configs | nightly Mon–Thu, ~12 h, 3 GPUs |
| ClimaCoupler `config/amip_configs` | Target AMIP, 3 simulated years | weekly, ~80 h |
| ClimaCoupler `config/longrun_configs` | Slabplanet → AMIP → CMIP → calibration | weekly, ~24 h |
| ClimaCoupler `config/benchmark_configs` | CPU/GPU SYPD, atmos-only vs coupled | weekly, ~16 h, posted to Slack |
| ClimaCoupler `experiments/CMIP` | AMIP + Oceananigans ocean | in long runs |
| ClimaAtmos `.buildkite/longruns_gpu`, `config/longrun_configs` | Held–Suarez, baroclinic wave, aquaplanet, `amip_target` | scheduled |
| ClimaLand `experiments/long_runs`, `.buildkite/longruns_gpu` | Global bucket, soil, snowy land | scheduled |
| Atmos `calibration/`, Land `experiments/calibration`, Coupler `experiments/calibration` | Calibration pipelines | ad hoc / weekly |

## Why centralize

1. **They already need the whole repo at HEAD.** The Coupler nightly
   pipeline has an `UPSTREAM_PACKAGES` step that `Pkg.add`s the `main`
   branch of 8 packages. ClimaAtmos's pipeline has the same mechanism for
   downstream triggers. That's a hand-built monorepo checkout. Here, every
   in-repo package already resolves to the checkout.
2. **They catch cross-package breaks, which is exactly the monorepo's job.**
   Right now the nightly pins ClimaLand to its release. ClimaLand#1882
   removed `Spaces.issubspace` for spectral-element space pairs, which
   ClimaCoupler's `Interfacer.remap!` still uses. As a scheduled experiment
   in another repo, that break is found after merge and papered over with a
   pin. With the monorepo's affected-package CI, the ClimaLand PR itself
   would have failed the coupler tests.
3. **They're the org's product metrics.** SYPD, AMIP skill, and
   conservation over time are what clima-perf tracks. One place for their
   configs, drivers, and result reporting makes that tracking one pipeline
   instead of three.
4. **ClimaCoupler gets smaller.** It becomes a component library (the
   interfaces, flux calculations, and remapping) instead of also being the
   org's simulation harness.

## Design

```text
experiments/
  amip/                 # nightly + weekly target AMIP, benchmarks
    Project.toml        # own env; [sources] → in-repo packages
    configs/            # (after the move) nightly/, target/, benchmark/
    run.jl              # (after the move) driver, today packages/ClimaCoupler/experiments/AMIP
  cmip/                 # AMIP + Oceananigans
  atmos-longruns/       # from ClimaAtmos config/longrun_configs
  land-longruns/        # from ClimaLand experiments/long_runs
  calibration/          # shared calibration drivers
.buildkite/experiments/<name>.yml   # scheduled pipelines, one per experiment
```

**Environments stay out of the root workspace.** Experiments pull in
CairoMakie, GeoMakie, CUDA, Oceananigans, and plotting stacks. Putting
those in the shared Manifest would constrain every package's tests. Instead,
each experiment has its own Manifest. `julia tools/mono.jl sources
experiments/<name>` makes **every** in-repo package it loads, including
transitive ones, a direct dep with a `[sources]` path.

The transitive part matters. `[sources]` only applies to direct deps, so
without it RRTMGP, CloudMicrophysics, RootSolvers, and ClimaInterpolations
would silently come from the registry. That's why the Coupler nightly's
`UPSTREAM_PACKAGES` has to list them by hand.

**Pinning is explicit and visible.** To run an experiment against a
release instead of HEAD, remove that package's `[sources]` line and add a
compat bound. The diff shows it in review. Today, a pin is an edit to an
environment variable in a pipeline file.

## Prototype: `amip/`

- `amip/Project.toml` is ClimaCoupler's `experiments/AMIP/Project.toml`,
  plus `[sources]` for all 18 in-repo packages (4 added transitively).
- [`.buildkite/experiments/amip-nightly.yml`](../.buildkite/experiments/amip-nightly.yml)
  ports the Coupler nightly. It keeps the same three AMIP jobs, drops the
  `UPSTREAM_PACKAGES` step, and runs the driver from `packages/ClimaCoupler`
  with the root environment. Configs resolve through
  `pkgdir(ClimaCoupler)`, so the driver works unchanged.

```bash
julia --project=experiments/amip -e 'using Pkg; Pkg.instantiate()'
julia --project=experiments/amip packages/ClimaCoupler/experiments/AMIP/run_simulation.jl \
    --config_file packages/ClimaCoupler/config/ci_configs/amip_default.yml
```

## Migration (once upstream sync stops)

1. `git mv` ClimaCoupler's `experiments/{AMIP,CMIP,calibration}` and the
   `amip_configs`, `nightly_configs`, `longrun_configs`, and
   `benchmark_configs` into `experiments/`. Keep `ci_configs` in the
   package, because those are its PR tests.
2. Same for ClimaAtmos `config/longrun_configs` + `.buildkite/longruns_gpu`
   and ClimaLand `experiments/long_runs`.
3. Replace `joinpath(pkgdir(ClimaCoupler), "config/...")` defaults in
   `ClimaCoupler.Input` with paths relative to the experiment.
4. Point the Buildkite schedules at `.buildkite/experiments/*.yml`. Delete
   the `UPSTREAM_PACKAGES` machinery.
5. Have each experiment emit a small JSON summary (SYPD, memory, key
   diagnostics) as a Buildkite artifact for clima-perf to ingest.

## Open questions

- **Ownership.** Today the Coupler team owns the AMIP pipelines. Centralized
  experiments need a named owner or on-call rotation, or they'll rot faster,
  not slower.
- **How much of ClimaCoupler's `Input`/driver layer belongs to the
  experiment vs. the package?** If most of the driver moves out, ClimaCoupler
  gets an actual public API for setting up a coupled run. That's good for
  users, but it's a design task.
- **Weekly and nightly budgets** are shared cluster time. Consolidating
  makes it easier to see and trim overlap, e.g. the ClimaAtmos
  `amip_target` long run vs. the Coupler target AMIP.
