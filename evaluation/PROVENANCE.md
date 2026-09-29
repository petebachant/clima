# Data provenance

Every number in [EVALUATION.md](../EVALUATION.md), [docs/OWNERSHIP.md](../docs/OWNERSHIP.md),
and [docs/PLAN.md](../docs/PLAN.md) comes from one of the sources below.
Times are UTC. "Pinned" means the exact input revision is recorded, so the
number can be reproduced. "Snapshot" means it came from a live API that
can't be replayed exactly.

## 1. clima-perf (2021-Q2 → 2026-Q3 baseline)

| | |
|:--|:--|
| Project | [calkit.io/petebachant/clima-perf](https://calkit.io/petebachant/clima-perf) · [github.com/petebachant/clima-perf](https://github.com/petebachant/clima-perf) |
| **Revision** | [`2765d08f0f5f1c37da293a93428dbcd142518c73`](https://github.com/petebachant/clima-perf/tree/2765d08f0f5f1c37da293a93428dbcd142518c73) ("Run pipeline", 2026-09-28T15:15:12Z) |
| Data through | GitHub data: last completed day **2026-09-27** (`data/github/.last_completed_day`); registry: run of 2026-09-27 (`data/julia-registry/latest_run.json`) |
| Status | Pinned. Outputs are produced by that revision's DVC pipeline (`dvc.lock`). |

Numbers used here, with permalinks at that revision:

| Number(s) | File |
|:--|:--|
| 688 releases, 34% reactive, 629 cascade events, 55% mechanical, ≈66 eliminable/yr, 724 propagation PRs, 5 of 19 with external dependents | [results/colocation-saving.json](https://github.com/petebachant/clima-perf/blob/2765d08f0f5f1c37da293a93428dbcd142518c73/results/colocation-saving.json) |
| Per-repo releases / reactive / mechanical events | [results/colocation-by-repo.csv](https://github.com/petebachant/clima-perf/blob/2765d08f0f5f1c37da293a93428dbcd142518c73/results/colocation-by-repo.csv) |
| 722 of 750 dependency updates within 14 days of a release | [results/repo-cochange-summary.json](https://github.com/petebachant/clima-perf/blob/2765d08f0f5f1c37da293a93428dbcd142518c73/results/repo-cochange-summary.json) |
| Example cascade (ClimaUtilities 2025-07-29) | [results/example-release-cascade.json](https://github.com/petebachant/clima-perf/blob/2765d08f0f5f1c37da293a93428dbcd142518c73/results/example-release-cascade.json) |

The Project.toml commit histories (`data/github/projecttoml/*.jsonl`) and
release lists (`data/github/releases/*.jsonl`) at the same revision were
also inputs to the 12-month lag analysis (§2). ClimaAtmos's Project.toml
commit count for the window matches between the two sources exactly.

## 2. 12-month baseline (2025-09-28 → 2026-09-28)

Data, scripts, and summary are in [baseline-2026-09/](baseline-2026-09/SUMMARY.md).
It was collected 2026-09-28, roughly 21:55–23:30 UTC.

**General registry** (sparse clone, `C/ I/ R/ S/ T/`): commit
[`d1ceb94bda13217ad95c30350d2f2fe4cb80aef3`](https://github.com/JuliaRegistries/General/tree/d1ceb94bda13217ad95c30350d2f2fe4cb80aef3)
(2026-09-28T21:53:44Z). Pinned. This is the source for version counts,
breaking releases, registry `Compat.toml`, and registration dates.

**Package clones** (blobless, `main`): pinned. These are the same commits
the monorepo's subtrees were imported from (§3), so the baseline and the
prototype describe the same code.

| Repo | Commit | Committed |
|:--|:--|:--|
| ClimaAtmos.jl | `d46a056e2ceef16f72a1ee79f902a5e30189a177` | 2026-09-26T20:44:12Z |
| ClimaCore.jl | `2d78120cdb9544af765002ef3af7798a01fb75c5` | 2026-09-28T19:27:36Z |
| ClimaCoupler.jl | `aae78809b3c37b8f458fd1d997b6bda8196d668f` | 2026-09-28T16:12:10Z |
| ClimaDiagnostics.jl | `e31d9a66b9d7b478ed14d22c9654b85e323d783b` | 2026-09-16T19:17:10Z |
| ClimaLand.jl | `5dc19d08cfc6bec65c2b6746ef598263f74298ee` | 2026-09-28T20:25:10Z |
| ClimaTimeSteppers.jl | `147598789cdf70a36bc2cef663898f1145ad97e8` | 2026-09-16T20:01:22Z |
| ClimaUtilities.jl | `75acdd17bde3af689aeee996ea27b749afa0198a` | 2026-09-24T23:52:39Z |
| CloudMicrophysics.jl | `7ffa9add18140e83c98faefe063e928b4c291cd6` | 2026-09-25T18:46:43Z |
| RRTMGP.jl | `eed2d3c6ae0b610a59fcb011e3176802d22a60c1` | 2026-09-25T20:22:48Z |
| SurfaceFluxes.jl | `838da3cf70c5b7a641f69121bebc0b7ff50679c8` | 2026-09-21T09:45:17Z |
| Thermodynamics.jl | `9f68819e4e299a38f9308ec1599dbc1fb52af4cb` | 2026-09-01T15:02:14Z |

**GitHub API** (`gh`), 2026-09-28 ~21:57–22:05 UTC: snapshot. This covers
merged PRs with changed files (`data/prs_classified.csv`), issues, workflow
runs of the "Downstream" workflows (`data/downstream_ci_main_runs.csv`), and
cross-repo references. Later edits to PRs or issues, and deleted workflow
runs, change what a re-query returns.

## 3. The monorepo's package snapshot

The squashed subtree imports (2026-09-28T21:55Z) record the upstream commit
each package came from, in the `git-subtree-split:` trailer of each
`chore(...): add subtree` commit. To list them:

```bash
git log main --grep=git-subtree-dir --format=%B |
    awk '/git-subtree-dir:/{d=$2} /git-subtree-split:/{print d, $2}'
```

| Path | Upstream commit |
|:--|:--|
| docs/dev (DeveloperGuides) | `087143e174bf3fab94f9662920607c7dfd0e99c1` |
| packages/ClimaAnalysis | `7652c03589db0561f3a1b65f5dd6fde550d6ec23` |
| packages/ClimaAtmos | `d46a056e2ceef16f72a1ee79f902a5e30189a177` |
| packages/ClimaCalibrate | `43ee6968f49f34b6142a9846837cae5929edefe6` |
| packages/ClimaComms | `c6d7a1ff24258f1aa3dfa4e43188d1e17c1b3fc2` |
| packages/ClimaCore | `2d78120cdb9544af765002ef3af7798a01fb75c5` |
| packages/ClimaCoupler | `aae78809b3c37b8f458fd1d997b6bda8196d668f` |
| packages/ClimaDiagnostics | `e31d9a66b9d7b478ed14d22c9654b85e323d783b` |
| packages/ClimaInterpolations | `3539fa3acf9d546de55817d6474b5a7f94b69611` |
| packages/ClimaLand | `5dc19d08cfc6bec65c2b6746ef598263f74298ee` |
| packages/ClimaParams | `5edf05638258ca472736b6940f55ef0b09b89984` |
| packages/ClimaTimeSteppers | `147598789cdf70a36bc2cef663898f1145ad97e8` |
| packages/ClimaUtilities | `75acdd17bde3af689aeee996ea27b749afa0198a` |
| packages/CloudMicrophysics | `7ffa9add18140e83c98faefe063e928b4c291cd6` |
| packages/Insolation | `bec8a04394616a33923775c03b32cdcb0e8987b3` |
| packages/RootSolvers | `7389b926dd93bad4d872f4b50a1e49208167fa3f` |
| packages/RRTMGP | `eed2d3c6ae0b610a59fcb011e3176802d22a60c1` |
| packages/SurfaceFluxes | `838da3cf70c5b7a641f69121bebc0b7ff50679c8` |
| packages/Thermodynamics | `9f68819e4e299a38f9308ec1599dbc1fb52af4cb` |

Findings made against the monorepo are pinned to these commits plus the
local changes committed on top:
- the 5 stale test bounds and FastBroadcast;
- the workspace resolve and load results;
- the formatter survey and the 423-file reformat measurement (monorepo
  `main` at `36c9a291b`);
- the example friction.

After a `tools/subtree.sh pull`, they may no longer hold.

## 4. The `issubspace` case study

All pinned:
- ClimaCore commit `e2db7268` (in PR [#2637](https://github.com/CliMA/ClimaCore.jl/pull/2637), merged 2026-09-16T15:21:14Z) removed the methods.
- The PR's check runs came from the GitHub checks API for that commit, queried 2026-09-28.
- "Still missing upstream" was checked against ClimaCore `main` on 2026-09-28. The subtree snapshot above, `2d78120c`, also lacks the methods.

## 5. Ownership and review load

[ownership-2026-09/](ownership-2026-09/): `fetch.py` (GraphQL query),
`owners.json` (raw per-repo reviewer and author counts), `proposed.json`
(derived owners).

This is a snapshot: merged PRs from 2025-09-28 onward, queried
2026-09-28 ~22:50 UTC. Bots are excluded. A reviewer counts once per PR.
Team membership (`gh api orgs/CliMA/teams`) is a snapshot from the same
time.

## 6. Other snapshots

| Number | Source | When |
|:--|:--|:--|
| 57 public non-archived org repos, 54 active, 47 `.jl` | `gh repo list CliMA` | 2026-09-28 ~22:30 UTC |
| gh-pages sizes (CloudMicrophysics 4.07 GB, …) | git tree blob sums of each repo's `gh-pages`, via the GitHub API (docs research) | 2026-09-28 |
| Repo sizes (ClimaAtmos ~284 MB, …) | `gh api repos/CliMA/<repo>` `size` | 2026-09-28 ~21:52 UTC |
| Workflow-file counts per repo | `gh api repos/CliMA/<repo>/contents/.github/workflows` | 2026-09-28 |

Neither the gh-pages branch SHAs nor the repo listing were recorded, so
these can't be reproduced exactly. Rerun the queries for current values.
