# Multi-repo baseline, 2025-09-28 → 2026-09-28

These are 12-month measurements of how the 18 in-scope packages release and
propagate today. The longer-window numbers (2021–2026) come from
[clima-perf](https://calkit.io/petebachant/clima-perf) and are summarized
in [../../EVALUATION.md](../../EVALUATION.md).

Inputs, with exact revisions, are listed in [../PROVENANCE.md](../PROVENANCE.md#2-12-month-baseline-2025-09-28--2026-09-28):
- General registry at `d1ceb94b`;
- 11 package `main` branches at the commits the monorepo imported;
- a GitHub API snapshot from 2026-09-28;
- clima-perf at `2765d08f`.

Raw data is in `data/` and the scripts that produced it are in `scripts/`.
The scripts expect the clones (General sparse clone, 11 blobless package
clones) they were run against, so they are for reference rather than
push-button reruns.

## Headline numbers

| Metric | Value |
|:--|:--|
| Registered versions, all 18 packages | 287 (≈5.5/week) |
| Breaking versions (major bump, or minor bump on 0.x) | 48 (17%) |
| Merged PRs | 1,975 (1,845 non-bot) |
| Release/compat/deps churn PRs | 322 (**16%** of merged) |
| Downstream upgrade PRs that also changed `.jl` code | 42 of 78 (**54%**) |
| **Breaking release → direct dependent admits it** | median **1.1 d**, p90 **9.7 d**, max **63 d** |
| Non-breaking release → direct dependent admits it | 94% already admitted; max 9.1 d |
| **Breaking release → reaches Atmos/Land/Coupler `main`** (end to end) | median **1.8 d**, p90 **14 d**, max **63 d**; 13 of 74 never |
| …→ reaches a *registered* Atmos/Land/Coupler | median **4.4 d**, p90 **29 d**, max **84 d**; 26 of 74 not yet |
| Upstream releases no dependent ever admitted | 11 of 180 |
| Upstream `main`-push runs of "Downstream" CI that failed | 389 of 1,233 (**32%**) |
| Merged PRs referencing a PR in another in-scope repo | 89 (4.8%) |
| Same infrastructure PR merged in 3+ repos | 16 changes, 116 PRs |

## A. Releases

| Package | Versions | Breaking | Median days between |
|:--|--:|--:|--:|
| ClimaAtmos | 51 | 11 | 7 |
| ClimaLand | 35 | 1 | 8.5 |
| ClimaParams | 34 | 0 | 8 |
| CloudMicrophysics | 33 | **13** (every minor 0.29 → 0.41) | 6.5 |
| ClimaCore | 24 | 3 | 9 |
| Thermodynamics | 18 | 2 | 8 |
| ClimaTimeSteppers | 17 | 3 | 4.5 |
| SurfaceFluxes | 13 | 4 | 16.5 |
| ClimaDiagnostics | 12 | 1 | 24 |
| RRTMGP | 10 | 3 | 31 |
| ClimaCalibrate | 10 | 5 | 34 |
| ClimaUtilities | 7 | 0 | 40.5 |
| Insolation | 5 | 1 | 37.5 |
| RootSolvers, ClimaAnalysis, ClimaCoupler | 4 each | 0 / 0 / 1 | — |
| ClimaComms, ClimaInterpolations | 3 each | 0 | — |

Breaking releases cluster. Two examples:
- 2026-03-09 → 03-12: Thermodynamics 1.0, CloudMicrophysics 0.32,
  SurfaceFluxes 1.0.
- 2026-08-10 → 09-22: ClimaCore 0.15, 0.16, 1.0; ClimaTimeSteppers 1.0;
  RRTMGP 0.23, 1.0; CloudMicrophysics 0.39 → 0.41.

## B. Churn

322 of 1,975 merged PRs (16%) are release, compat, or dependency-only work.
The share is highest in the downstream apps:

| Repo | Churn % |
|:--|--:|
| ClimaDiagnostics | 35% |
| ClimaLand | 23% |
| ClimaCoupler | 19% |
| ClimaUtilities | 19% |
| ClimaAtmos | 14% |

Title/file heuristic, roughly ±20%.

Of the 78 human upgrade PRs in Atmos, Land, and Coupler that name an
in-scope upstream, 54% also changed code. So they were real adaptations,
not just compat edits. Median time open was 0.84 d; the longest was 56 d.
Examples: Atmos#4151 (ClimaDiagnostics 0.3, 48 days, ~1.7k lines) and
Atmos#4624 (RRTMGP API, 14 days).

## C. Propagation lag

**Method.** For each of 180 releases from 12 upstreams, and each in-set
dependent listing that upstream in `[deps]`/`[weakdeps]`:
- read every first-parent `main` commit touching `Project.toml` (for
  ClimaCoupler, also `experiments/ClimaEarth/Project.toml`);
- evaluate `Pkg.Versions.semver_spec` against every registered version.

Lag = 0 if compat already admitted the version; otherwise, days until the
first admitting commit. Cross-checked against clima-perf's Project.toml
commit counts.

| | Pairs | Already admitted | Median | p90 | Max | Never | Superseded |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Breaking | 73 | 2 | 1.10 d | 9.73 d | 63.3 d | 7 | 14 |
| Non-breaking | 648 | 612 (94%) | 0 | 0 | 9.1 d | 9 | 17 |

Selected edges (breaking releases, days):

| Edge | n | Median | Max |
|:--|--:|--:|--:|
| ClimaCore → Atmos / Land / Coupler | 3 | 1.1 / 0.7 / 0.7 | 1.4 / 1.1 / 1.2 |
| ClimaTimeSteppers → Atmos / Land / Coupler | 3 | 3.0 / 3.0 / 3.1 | 4.9 / 8.4 / 5.1 |
| CloudMicrophysics → Atmos | 13 | 0.84 | **27.1** |
| SurfaceFluxes → Atmos / Land / Coupler | 4 | 1.2 / 1.0 / 3.8 | 17.7 / 9.8 / 18.7 |
| Thermodynamics → Atmos / Land / Coupler | 2 | 5.4 / 0.9 / 6.4 | 9.7 / 1.8 / 10.8 |
| **ClimaDiagnostics 0.3 → Atmos / Coupler** | 1 | **55.2 / 63.3** | |

**End to end**, through intermediates, using registry compat for
intermediates and the sink's `main` or registered versions:

| Sink | Breaking releases | `main`: median / p90 / max, never | registered: median / p90 / max, not yet |
|:--|--:|:--|:--|
| ClimaAtmos | 30 | 1.15 / 13.7 / 55.2 d, 4 | 3.0 / 16.2 / 59.1 d, 5 |
| ClimaLand | 14 | 1.03 / 7.9 / 9.8 d, 2 | 3.1 / 8.7 / 16.7 d, 2 |
| ClimaCoupler | 30 | 4.06 / 26.1 / 63.3 d, 7 | 7.5 / 48.9 / 84.2 d, 19 |
| All | 74 | 1.8 / 14.1 / 63.3 d, 13 | 4.4 / 29.1 / 84.2 d, 26 |

**Chain depth doesn't predict lag.** The ClimaCore 0.15/0.16/1.0 cascades
reached Coupler in 0.75–2.0 days, because they were coordinated ahead of
time. The long tail comes from single-edge laggards: ClimaDiagnostics 0.3,
CloudMicrophysics 0.37, and SurfaceFluxes 0.13/0.15.

RootSolvers 1.0.1/1.0.2 took 71–90 days to reach Coupler `main`, held back
by Coupler's own compat.

**Never adopted:** CloudMicrophysics 0.31.0–0.31.7, RRTMGP 0.22.0–0.22.1,
Insolation 1.0.0. Each was superseded before any dependent picked it up.

## D. Downstream breakage

Downstream CI on upstream `main` pushes:

| Workflow | Runs | Failed |
|:--|--:|--:|
| ClimaCore/Downstream | 156 | 42% |
| ClimaUtilities/downstream | 47 | 47% |
| ClimaDiagnostics/Downstream | 40 | 43% |
| SurfaceFluxes/downstream | 61 | 36% |
| Thermodynamics/Downstream | 59 | 32% |
| **Thermodynamics/Downstream-ClimaCoupler** | 70 | **100%** (red 2025-12 → 2026-08, then stopped) |
| ClimaLand/downstream | 227 | 36% |
| ClimaAtmos/downstream | 512 | 17% |
| ClimaTimeSteppers/downstream | 44 | 0% |

These are advisory. Buildkite downstream triggers are `soft_fail`, and
upstream merged while they were red. The failures mix real upstream breaks,
downstream flakiness, and infrastructure.

Confirmed breakage examples:
- [Coupler#1648](https://github.com/CliMA/ClimaCoupler.jl/pull/1648): Thermodynamics breaking change
- [Coupler#1633](https://github.com/CliMA/ClimaCoupler.jl/pull/1633): SurfaceFluxes main incompatible
- [Coupler#1883](https://github.com/CliMA/ClimaCoupler.jl/pull/1883): a ClimaLand PR broke Coupler in two ways
- [Land#1754](https://github.com/CliMA/ClimaLand.jl/pull/1754): regression from a new ClimaCore release
- The same "replace ClimaCore names removed in v0.16" fix, made three times:
  [Atmos#4814](https://github.com/CliMA/ClimaAtmos.jl/pull/4814),
  [Land#1872](https://github.com/CliMA/ClimaLand.jl/pull/1872),
  [Coupler#2110](https://github.com/CliMA/ClimaCoupler.jl/pull/2110)

## E. Coordinated changes

89 of 1,845 non-bot merged PRs (4.8%) reference a PR or issue in another
in-scope repo; 17 use explicit dependency wording. The top pairs:
Coupler→Atmos (13), ClimaCore→Atmos (7), Coupler→Land (7).

Examples:
- RRTMGP#601 + Atmos#4624 + Coupler#2009
- Coupler#2101 (needs Atmos#4801 and Land#1869)
- Atmos#4734 (needs CloudMicrophysics #767 and #768)

16 infrastructure changes were replicated across 3+ repos, 116 PRs in
total. The CLA workflow alone accounts for 16–18 PRs per change.

## F. Existing downstream CI

Ten upstreams have hand-maintained downstream workflows: ClimaCore, RRTMGP,
Thermodynamics, SurfaceFluxes, CloudMicrophysics, ClimaTimeSteppers,
ClimaUtilities, ClimaDiagnostics, ClimaLand, ClimaAtmos. Each clones a
downstream's `main` and `Pkg.develop`s itself.

ClimaComms, ClimaParams, RootSolvers, ClimaInterpolations, Insolation,
ClimaAnalysis, and ClimaCalibrate have none. ClimaComms and RootSolvers sit
at depth 5 under Coupler.

## Caveats

1. "Breaking" is judged from the semver number only.
2. Registry dates are merge times into General.
3. The churn classification is a title/file heuristic.
4. Lag measures when compat *admitted* a version, not when the pair worked.
   Adaptation often happens on branches before the release, so real
   coordination effort is higher than the lag suggests.
5. Experiment Manifests are not tracked.
6. The end-to-end model is a simplified resolver. It ignores non-CliMA and
   Julia-version constraints.
7. CI failure counts don't separate upstream-caused from downstream-caused
   failures.
8. Keyword scans miss Slack, PR comments, and bare `#N` references.
