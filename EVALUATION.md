# Is consolidating worth it?

This repo exists to answer four questions with evidence, not intuition:

1. **Will it make releasing faster?**
2. **Will it reduce breaking changes reaching downstream?**
3. **Will it reduce the maintenance burden of releases?**
4. **Will it make it easier for users to find what they need?**

For each question: what we expect, how we'll measure it, what the
multi-repo baseline is, and what we've seen so far.

## Baseline (multi-repo)

From [clima-perf](https://calkit.io/petebachant/clima-perf) at revision
[`2765d08f`](https://github.com/petebachant/clima-perf/tree/2765d08f0f5f1c37da293a93428dbcd142518c73)
(GitHub + General registry data for 35 CliMA repos through 2026-09-27;
2021-Q2 → 2026-Q3, 5.2 years). Cascade window = 14 days. Every number's
source file, and the revisions of all other inputs, are in
[evaluation/PROVENANCE.md](evaluation/PROVENANCE.md).

| | Value |
|:--|:--|
| Releases by tracked packages | 688 (131/yr) |
| …of which **reactive** (upstream-driven, exist only to keep the version graph consistent) | 233 (**34%**) |
| Dependency updates landing within 2 weeks of another package's release | 722 of 750 (**96%**) |
| Cascade events | 629 (120/yr) |
| …**mechanical** (compat/manifest bookkeeping a shared repo absorbs) | 349 (**55%**) → ≈66 PRs/yr eliminable |
| …substantive (interface adaptation, still real work) | 280 (45%) |
| Propagation PRs by title (cross-check) | 724 of 12,262 merged (138/yr) |
| Releasing packages with *any* external registry dependents | **5 of 19** |

Per repo (busiest first), from `colocation-by-repo.csv`:

| Repo | Releases | Reactive | Mechanical events/yr |
|:--|--:|--:|--:|
| ClimaAtmos | 110 | 67 | 9.9 |
| ClimaCore | 103 | 38 | 7.4 |
| ClimaLand | 74 | 34 | 4.2 |
| CloudMicrophysics | 56 | 11 | 1.7 |
| Thermodynamics | 53 | 4 | 0.6 |
| ClimaTimeSteppers | 47 | 16 | 2.7 |
| ClimaParams | 44 | 2 | 0.8 |

(ClimaOcean, EKP and CalibrateEmulateSample are also high on mechanical
events, but they're outside this monorepo's scope.)

clima-perf's own conclusion: the PR-count saving is modest, because
propagation PRs already merge in under a day. The bigger cost is the
per-release ritual, most of which serves no one outside the org.

**Last 12 months**, measured directly. Details, per-edge tables, and data
are in [evaluation/baseline-2026-09/](evaluation/baseline-2026-09/SUMMARY.md).
Inputs: General registry at `d1ceb94b` and package `main` branches at the
same commits the monorepo imported
([PROVENANCE §2](evaluation/PROVENANCE.md#2-12-month-baseline-2025-09-28--2026-09-28)).

| | Value |
|:--|:--|
| Registered versions / breaking | 287 / 48 (17%) |
| Release/compat/deps churn PRs | 322 of 1,975 merged (16%) |
| Upgrade PRs that also had to change code | 54% |
| **Breaking release → direct dependent's `main` admits it** | median **1.1 d**, p90 **9.7 d**, max **63 d** |
| **Breaking release → Atmos/Land/Coupler `main`** (end to end) | median **1.8 d**, p90 **14 d**, max **63 d**; 13 of 74 never |
| **…→ a registered Atmos/Land/Coupler** | median **4.4 d**, p90 **29 d**, max **84 d**; 26 of 74 not yet |
| Upstream `main` pushes whose Downstream CI was red | 32% (advisory; merged anyway) |
| Thermodynamics → ClimaCoupler downstream job | red on 100% of 70 runs for 8 months |
| Same fix made separately in 3 repos | e.g. ClimaCore 0.16 renames: Atmos#4814, Land#1872, Coupler#2110 |

**The typical case is already fast.** A coordinated breaking release
reaches the models in about a day; the ClimaCore 0.15/0.16/1.0 cascades
reached Coupler in under 2 days.

**The cost is in the tail and in what the lag hides:**
- a p90 of two weeks, and outliers of two months (ClimaDiagnostics 0.3:
  55–63 days to Atmos/Coupler);
- users waiting a median 4.4 days (p90 a month) for a *registered*
  model that works with an upstream breaking release;
- a third of downstream CI runs red on upstream `main`, and ignored.

Lag also only measures when compat admitted a version, not the adaptation
work done on branches beforehand.

## Case study: the `issubspace` outage (September 2026)

A real break that became a major outage, and the clearest evidence so far
for Q2.

**What happened.**
1. **The change.** ClimaCore PR
   [#2637](https://github.com/CliMA/ClimaCore.jl/pull/2637) ("Updated
   scaling plots", merged 2026-09-16) included commit `e2db7268`
   ("Additional docs updates"). It deleted the `issubspace` methods for
   spectral-element spaces from `src/Spaces/spectralelement.jl`. The
   docstring that points to them is still there.
2. **Why it mattered.** ClimaCoupler's `Interfacer.remap!` relies on those
   methods to move atmosphere surface fields onto the boundary space.
   Without them, **every global coupled run** fails with "Cannot remap
   between distinct spectral-element spaces".
3. **What CI said.** On that PR, "downstream ClimaCoupler.jl" and
   "downstream ClimaLand.jl" **failed**. They are advisory, so it merged
   anyway, and ClimaCore has no `issubspace` unit test.
4. **What happened next.** ClimaCoupler's nightly AMIP pipeline pinned
   ClimaLand to a release. Its comment attributes the break to ClimaLand.
   Two weeks later, upstream ClimaCore `main` still lacks the methods.

**Where the monorepo would have stopped it.**
- `mono.jl affected` on that PR lists ClimaCore plus all 7 of its
  dependents, including ClimaCoupler, ClimaLand, and ClimaAtmos.
- With required checks, the ClimaCoupler test failure blocks the merge.
  Today that same failure is a red X someone can ignore.
- The `coupled-slabplanet` example (nightly) and the `experiments/amip`
  prototype both exercise this path. Writing that example is what
  rediscovered the bug.

**The fix, done the monorepo way.** It's on branch
`fix/climacore-issubspace`:
- One change restores the two ClimaCore methods and adds a regression test
  for the exact case the coupler needs. The test fails without the fix
  and passes with it.
- The same branch fixes a second bug the example found: ClimaCoupler's
  bucket model leaves `output_writer` unassigned when land diagnostics
  are off.
- It removes both workarounds from the example.

That's one PR across two packages and an example, reviewed by both sets of
owners and tested together. In the multi-repo world, it would be a
ClimaCore PR, a ClimaCore release, a ClimaCoupler PR, a ClimaCoupler
release, and an unpin.

**Caveat.** The monorepo doesn't prevent the *mistake*. It makes the
consequence visible and blocking on the PR that caused it. That only works
if downstream checks are *required*, and flaky downstream tests would make
people want them advisory again. Budgeting for test reliability is part of
the cost of Q2.

## What the first full CI run found (2026-09-29)

The first CI run to get past planning, GitHub Actions run 36635294994 at
`434a897f9`, tested all 18 packages on Julia 1.12 and LTS against each
other's in-repo HEAD. It surfaced three cross-package problems that no
standalone repo's CI reports today:

| Where | What | Why per-repo CI misses it |
|:--|:--|:--|
| ClimaAtmos `test/parameter_tests.jl:117` | Asserts `sgs_variance_horizontal_scale_factor` "must default to 0 so the historical closure is reproduced bitwise"; ClimaParams `main` sets it to **3.0** (and `sgs_variance_geometric_Ri_factor` to 1.0). | ClimaAtmos CI pins an older ClimaParams; ClimaParams has no ClimaAtmos downstream test. It surfaces only after the next ClimaParams release reaches ClimaAtmos. |
| ClimaUtilities `test/timemanager.jl:9` | Fails with ClimaTimeSteppers 1.x (`ClimaODEFunction` no longer satisfies SciMLBase's `isinplace`). | The test env pinned `ClimaTimeSteppers = "0.8.2"`, one of the "stale bounds" above. The bound wasn't just stale: it was **hiding** that ClimaUtilities' tests don't work with the current ClimaTimeSteppers. |
| ClimaAtmos `ext/ClimaAtmosMusica` | Overwrites `chemistry_tendency!(…, ::GasPhaseChem)` from the main module, which errors during precompilation of the extension. | Only shows when Musica is in the environment; the shared workspace has it. |

A fourth, ClimaCore `test/DataLayouts/unit_layout_args.jl:118`
(`UndefVarError: d1 not defined in Main` inside a MultiBroadcastFusion
macro), happens under `Pkg.test()`. MultiBroadcastFusion is at the same
version (0.3.4) as in ClimaCore's own CI Manifest, so this is probably a
difference in how the test file is run, not version drift. Not yet
diagnosed.

The same run also hit bugs in the prototype's own plumbing, all fixed:
- Examples ran before the (uncommitted) workspace Manifest was instantiated.
- The LTS path for `[extras]`/`[targets]` packages developed in-repo deps
  into a copy of the package's own `Project.toml`, which made Aqua's
  `deps_compat`/`stale_deps` checks fail (ClimaAtmos, ClimaDiagnostics,
  ClimaCalibrate). It now builds a separate environment, as `Pkg.test` does.

## What the prototype showed on day one

Importing 18 packages and resolving them in **one** Julia workspace, the
first time anyone has tried to resolve them together, surfaced five stale
bounds that no standalone repo's CI had caught. All five are in **test
environments**, which per-repo CI resolves in isolation:

| Where | Bound | Problem |
|:--|:--|:--|
| ClimaUtilities `test/Project.toml` | `ClimaTimeSteppers = "0.8.2"` | CTS is at 1.0.1; ClimaUtilities tests an old CTS |
| ClimaTimeSteppers `test/Project.toml` | `CUDA = "5"` | package itself allows CUDA 6 |
| RootSolvers `test/Project.toml` | `CUDA = "4, 5"` | same |
| Thermodynamics `test/Project.toml` | `JET = "0.8, 0.9"` | no JET 0.8/0.9 installs on Julia 1.12, so JET tests can't run there |
| ClimaCore `[extras]` | `JET = "0.9"` | same |

Once those were widened, all 18 packages plus 12 test environments
resolved to one 312-package Manifest, and the key packages loaded from it
(ClimaAtmos, ClimaLand, ClimaCoupler, ClimaCalibrate, …).

Sample test runs, all passing:

| Package | How | Time |
|:--|:--|--:|
| ClimaParams (`[targets]` style) | 1.12 workspace, `Pkg.test()` | 8 s |
| Thermodynamics (`test/Project.toml`, widened JET) | 1.12 workspace, `Pkg.test()` | 88 s |
| SurfaceFluxes | 1.12 workspace, `Pkg.test()` | 266 s |
| SurfaceFluxes | 1.10 LTS, `mono.jl test` (devs 4 in-repo deps) | 184 s |

The source layout didn't matter; the dependency *metadata* was
where the rot was. `mono.jl compat --strict` now fails CI on this class of
problem.

Other observations:

- **The shared workspace couples unrelated environments.** Adding the
  `examples/` environments pulled in FastBroadcast 1.x, which conflicted
  with ClimaCore's test-only pin of `FastBroadcast = "0.3.1"`. Usually
  that's the point: it's how the five stale bounds above were found. But it
  also means one new example or test dependency can force changes in
  another package's test setup. If this becomes a nuisance, split the
  workspace: packages + test envs in one, examples/experiments resolved
  per directory against in-repo paths via `[sources]`.

- **Two test conventions.** 7 packages use `[extras]`/`[targets]`, 11 use
  `test/Project.toml` (ClimaInterpolations has both). Only the latter can
  join the workspace as test envs, so fast single-file test runs work for
  some packages and not others. Standardizing on `test/Project.toml` is a
  cheap migration step.
- **Repo size is fine.** Squashed subtrees: 134 MB `.git`, ~30 s to import
  everything. Full history would be far larger (ClimaAtmos alone is ~280 MB
  on GitHub); we don't need it here while upstream remains canonical.
- **A breaking bump is one command.** `mono.jl bump ClimaComms minor
  --release-dependents` edits ClimaComms plus 8 dependents' compat
  (including a test env the manual process would likely miss) and
  patch-bumps them. `register.sh --dry-run` then shows 9 registrations in
  dependency order.

## Question 1: Faster releases?

**Hypothesis.** Release *latency* for a change that spans packages drops
from "N sequential PR → review → merge → register → CompatHelper → PR"
cycles to one PR plus an automated cascade. Single-package patch releases
get no faster; they may get slightly slower, because CI tests downstream.

**Where the time goes today.** For an upstream breaking release to reach a
model: register upstream (wait for General AutoMerge) → someone notices
downstream → compat PR in each dependent → review → merge → register
each → repeat per tier. The dependency graph here is 4 tiers deep in hard deps, 5 counting ClimaCoupler's weak dep on ClimaAtmos
(ClimaComms → ClimaCore → ClimaDiagnostics → ClimaAtmos → ClimaCoupler).

**In the monorepo.** The compat edits happen in the upstream PR, CI proves
the whole graph works, and `register.sh` walks the tiers automatically.
The remaining latency is General's AutoMerge per tier, which we can't
remove.

**Measure.**
- *Adoption lag*: days from an upstream breaking release to each
  dependent admitting it in `[compat]` (baseline above; monorepo target:
  0, same PR).
- *Wall-clock* for a cascade: merge commit → last registration merged
  (read from register.yml run time).
- *PR count per cross-cutting change*: baseline from coordinated-PR
  evidence above; monorepo: 1.

## Question 2: Fewer breaking changes downstream?

**Hypothesis.** It won't reduce the number of *breaking releases*. API
evolution continues. It should nearly eliminate *surprise breakage*:
downstream failures found after a release. The author of an upstream
change sees downstream CI fail on their own PR, before merge.

It may also *lower* the number of breaking releases. When fixing every
caller is cheap and visible, a change can often be made non-breaking, or
deferred until callers are migrated in the same PR.

**Risk.** The flip side is that "test everything downstream" makes
upstream PRs slower and occasionally blocked by an unrelated downstream
flake. `affected` limits this to the actual reverse-dependency closure, and
foundation packages (ClimaComms, RootSolvers, ClimaParams) will pay the
most.

**Measure.**
- Downstream-breakage issues/PRs per month (baseline above).
- Breaking releases per package per year (baseline above).
- For foundation packages: median PR CI time before/after, and number of
  PRs blocked by a failure in a *downstream* package.

## Question 3: Less release maintenance?

**The catch.** A monorepo does **not** remove reactive releases by itself.
If ClimaCore makes a breaking change, users can combine it with ClimaAtmos
only once a ClimaAtmos release admits it. The 34% of releases that are
reactive still have to happen. What changes is who does them:
`mono.jl bump --release-dependents` plus `register.sh` turn them from
per-repo human chores into one command and an automated cascade. Actually
*eliminating* them means merging internal-only packages. That's a separate
decision, which the "5 of 19 have external users" number argues for. The
candidates are the packages with no external dependents that only exist
to serve the models: ClimaUtilities, ClimaDiagnostics, ClimaInterpolations.

**Hypothesis.** Yes, mostly by deleting work:
- CompatHelper PRs between in-repo packages disappear (compat is widened
  in the upstream PR, and `compat --strict` enforces it).
- Per-repo copies of CI, TagBot, docs cleanup, formatter, CLA, and
  dev-guide sync workflows (5–13 workflow files per repo today, e.g. ClimaComms 5, ClimaCore 12, ClimaAtmos 13) become one set.
- DeveloperGuides stops being vendored 10 times.
- **One formatting style.** Today, 17 of 18 packages use JuliaFormatter
  (Insolation has no config) with 11 different configurations: margins of
  80, 92, and 120, plus differing options. Only ClimaAtmos and ClimaCore
  have pre-commit hooks. The root setup, adopted from ClimaAtmos, already
  covers repo-level code.

  Measured cutover cost (delete the per-package configs, format
  everything): **423 files, +13,168 / −7,639 lines, 11 s**. Most of it is
  CloudMicrophysics (89 files; margin 120 today) and ClimaLand (98 files;
  margin 80). ClimaAtmos and ClimaCore change 1 file each. 9 files crash
  the pinned JuliaFormatter 2.10.1 and need `#! format: off` or a fix
  first. It's a one-time commit, listed in `.git-blame-ignore-revs`.
- Downstream CI workflows that clone other repos (e.g. ClimaAtmos →
  ClimaCoupler) become the default behavior, not a hand-maintained file.

**New costs.**
- One-time: move each package's General registry entry to this repo with
  `subdir` (a manual PR to General per package, ≈18 PRs).
- Per-package Buildkite pipelines (ClimaAtmos's especially) need porting
  to run from a subdirectory.
- Per-package docs sites need a new home (see Docs, below).
- Tag namespace changes to `<Pkg>-vX.Y.Z`; anything that parses tags
  (Documenter versioned docs, scripts) must follow.
- Issues and permissions become shared. Label and CODEOWNERS discipline
  replaces repo boundaries: see [docs/OWNERSHIP.md](docs/OWNERSHIP.md).
  Review load is already concentrated: one reviewer did 487 reviews across
  these repos last year. Required code-owner review must use teams with
  load-balanced assignment, or it will make that worse.

**Measure.**
- Merged "compat / version bump" PRs as a fraction of all merged PRs
  (baseline above).
- Count of CI/workflow files maintained: baseline vs here.
- Maintainer-minutes per release: time a few real releases both ways
  during the trial.

## Question 4: Easier for users to find what they need?

**Today.** The CliMA org has 57 public, non-archived repos; 54 were pushed
in the last year and 47 are `.jl` packages. The org profile README already
curates ~15 "key repositories", grouped by role. So a user who reads it
gets a component map, not a map by *task*. "I want to run a single-column
atmosphere case", "I want CliMA's microphysics in my own model", and "I
want to calibrate a land parameter" each mean assembling 3–8 packages
whose compatible versions you have to discover yourself.

**Hypothesis.** The monorepo by itself helps only a little with *finding*
things:

- If the 18 standalone repos are archived once they move, the org drops
  from ~57 active public repos to ~39. That's fewer places to look, but
  still a lot.
- Packages don't merge. Users still pick among 18 names.

It helps a lot with the things that actually confuse users once they've
found the right package:

- **One version set known to work together.** Today "which ClimaCore goes
  with this ClimaAtmos?" is answered by the resolver, or by trial and
  error. Here, every `main` commit is a tested combination, and releases
  come out as coordinated batches.
- **One docs site with a task-oriented front page**, instead of 18 sites
  that each describe one component (see Docs).
- **Tested use-case recipes.** A top-level `usecases/` directory, one small
  environment per task, run in CI. That turns "how do I do X" from tribal
  knowledge into a file that's guaranteed to work at HEAD. This isn't
  impossible in the multi-repo world, but nobody owns cross-package
  examples there, so they rot.

**Risks that make it *more* confusing:**

- Standalone-library users (e.g. people using Thermodynamics.jl or
  RRTMGP.jl outside CliMA's models) land on an archived repo from search,
  and they file issues in a repo where their package is 1 of 18. That needs
  clear redirect READMEs, and issue templates/labels per package.
- GitHub shows the monorepo README at the top, not the package's. Package
  READMEs live one click deeper.
- Stars, watchers, and "used by" counts reset for the moved packages.

**Measure.**
- Qualitative: give 3–5 new users (e.g. incoming students) a task. Compare
  time-to-first-successful-run with the current org vs the monorepo
  README + recipes.
- Issues labeled `question` / "how do I" per month, before vs after.
- Docs analytics: landing-page → package-page paths, and search terms with
  no results.

## How to run the trial

1. Keep syncing upstream weekly (`sync-upstream.yml`). CI here then
   shows, for free, every time an upstream `main` breaks a downstream
   `main`. That count alone is evidence for Q2, gathered before anyone
   changes their workflow.
2. Pick 2–3 real cross-cutting changes from the backlog, for example a
   ClimaCore API change that touches Atmos and Land. Do each here as one
   PR, and record PR count, wall-clock to released, and reviewer count.
   Compare with the coordinated-change examples in the baseline.
3. Pick one package with low traffic and simple CI (e.g. ClimaParams or
   RootSolvers) and actually move its registration to the monorepo. That
   exercises the General `subdir` PR, register.yml, and TagBot end to end.
4. Decide. Suggested bar: consolidate if cross-cutting changes are clearly
   cheaper *and* foundation-package PR CI stays under an agreed ceiling
   (e.g. 45 min on GitHub Actions).

## Open questions

- **Docs:** plan in [docs/PLAN.md](docs/PLAN.md): per-package builds merged by MultiDocumenter; GitHub Pages' 1 GB limit means stable + dev only.
- **Commit the workspace Manifest?** Not committed now, so CI resolves
  fresh like today's library CI. Committing it would make CI reproducible,
  but then something has to bump it on a schedule.
- **Buildkite:** port ClimaAtmos/ClimaCoupler/ClimaLand pipelines, or keep
  them in their packages and trigger them from the root pipeline?
- **Registrator + AutoMerge ordering:** `register.sh` waits for each
  upstream version to land in General. Verify on a real cascade that
  AutoMerge doesn't reject dependents opened slightly early.
- **ClimaCoupler's weak deps on ClimaAtmos/ClimaLand** make the Coupler
  effectively an integration test for the whole graph. That's good for
  coverage, but its tests are slow and will run on almost every PR.
