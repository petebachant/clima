# One docs site: plan

Status: proposed, not built. `docs/dev/` (DeveloperGuides) is already in
place.

## Recommendation

**Build each package's docs separately, then merge the built sites into one
with [MultiDocumenter.jl](https://github.com/JuliaComputing/MultiDocumenter.jl).**

- Each `packages/<Pkg>/docs/make.jl` keeps its own environment and build.
  Only its `deploydocs` call changes.
- A small hub at the root `docs/` holds a task-oriented landing page and
  the developer guides (`docs/dev/`).
- An aggregate step downloads the built HTML (no package code runs) and
  merges it into one site with a shared navbar and cross-package search
  (PageFind).

This is the pattern
[GraphNeuralNetworks.jl](https://github.com/JuliaGraphs/GraphNeuralNetworks.jl/blob/master/docs/make-multi.jl)
uses for a monorepo with independently versioned subpackages. Other users
include JuliaAstro/EphemerisSources.jl, SciMLDocs, and Sienna.

### Why not one Documenter build (the Makie approach)

Makie can do a single build because all its packages release together
under one tag. CliMA packages version independently. A single build would
also mean:

- one huge docs environment;
- a build as long as all of ClimaAtmos + ClimaLand + CloudMicrophysics's
  Literate examples combined;
- any one failing doctest blocking every package's docs.

### The constraint that shapes everything: size

GitHub Pages sites are limited to
[1 GB](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits).
Current gh-pages branches:

| Package | Total | Versions | `previews/` | One version |
|:--|--:|--:|--:|--:|
| CloudMicrophysics | 4.07 GB | 105 | 1.25 GB | 37 MB |
| ClimaAtmos | 2.84 GB | 128 | 2.24 GB | 7 MB |
| ClimaCore | 1.89 GB | 116 | 1.42 GB | 10 MB |
| ClimaLand | 1.86 GB | 62 | 1.09 GB | 17 MB |
| Thermodynamics | 0.78 GB | 79 | — | 5 MB |

So the combined site publishes **stable + dev** per package, roughly
0.3–0.5 GB for all 18. Older versions stay frozen on the existing
`clima.github.io/<Pkg>.jl` sites, linked via "all versions". PR previews
become CI artifacts instead of Pages branches.

## Pieces

**Store repo** (`CliMA/ClimaDocsStore`): one branch per package, each force-pushed
so it stays one commit. Separate from the monorepo so `git clone` of the
monorepo doesn't fetch GBs of HTML. One `DOCUMENTER_KEY` deploy key.

**Per-package `deploydocs`** (requires Documenter ≥ 1.11 for `deploy_repo`):

```julia
deploydocs(;
    repo = "github.com/CliMA/clima.git",
    deploy_repo = "github.com/CliMA/ClimaDocsStore.git",
    branch = "ClimaCore",
    tag_prefix = "ClimaCore-",   # matches TagBot subdir tags, ClimaCore-v1.2.3 → v1.2.3/
    devbranch = "main",
    forcepush = true,
    push_preview = false,
)
```

Also set `inventory_version = string(pkgversion(ClimaCore))` in
`Documenter.HTML`, as Documenter recommends for monorepos. Point
DocumenterInterLinks `@extref` targets at the combined-site URLs.
ClimaAtmos, ClimaCore, ClimaLand, and CloudMicrophysics already use
InterLinks. A shared `docs/common.jl` would keep the 18 `make.jl` files
consistent.

**Root `docs/`:**

```text
docs/
  Project.toml   # Documenter, DocumenterInterLinks, MultiDocumenter
  make.jl        # hub: src/index.md + dev guides → build/hub (versions = nothing)
  aggregate.jl   # fetch store branches → MultiDocumenter.make → build/site
  src/index.md   # task-oriented landing page (links to usecases/)
  dev/           # DeveloperGuides subtree
```

`aggregate.jl` downloads each store branch as a codeload tarball (as
SciMLDocs does), keeps `stable` and `dev` with
`VersionSelection(["stable", "dev"]; all_versions_url = ...)`, and groups
the navbar:

- **Core:** ClimaComms, ClimaCore, ClimaTimeSteppers, ClimaUtilities,
  ClimaInterpolations, RootSolvers, ClimaParams
- **Physics:** Thermodynamics, CloudMicrophysics, SurfaceFluxes,
  Insolation, RRTMGP
- **Models:** ClimaAtmos, ClimaLand, ClimaCoupler
- **Workflow:** ClimaDiagnostics, ClimaAnalysis, ClimaCalibrate

It should fail if the output exceeds ~900 MB.

**`.github/workflows/docs.yml`:**

- **plan:**
  - On a tag, the matrix is `${GITHUB_REF_NAME%-v*}`.
  - On cron or dispatch, only the aggregate runs.
  - Otherwise the matrix is `julia tools/mono.jl affected <base> --docs`.
    Downstream packages are included on purpose: upstream changes break
    their examples and doctests too.
- **build** (matrix, `fail-fast: false`):
  - Instantiate `packages/$PKG/docs` and run its `make.jl`.
  - On PRs, upload `docs/build` as an artifact instead of deploying.
  - Heavy packages keep their own timeouts, or move to Buildkite.
- **aggregate** (not on PRs):
  - Build the hub, run `aggregate.jl`, then `actions/deploy-pages`.
  - A package whose build failed keeps its last good version in the store,
    so one broken package never takes the site down.
- **TagBot** must push tags with an SSH key. Tags pushed with
  `GITHUB_TOKEN` don't trigger workflows, so docs wouldn't deploy.

Keep docs environments **out** of the root `[workspace]`. They'd drag
Documenter, CairoMakie, etc. into the shared Manifest. Use `[sources]`
paths to sibling packages instead; ClimaAtmos, CloudMicrophysics, and
RootSolvers already do.

## Migration

1. Create the store repo and its deploy key. Seed each package branch
   with dev + stable + latest release from the current gh-pages, leaving
   out `previews/`.
2. Update the 18 `deploydocs` calls and require Documenter ≥ 1.11.
3. Add the root `docs/`, `docs.yml`, and the TagBot SSH key.
4. Move `@extref` targets to the combined-site URLs.
5. Remove the per-package `docs/dev-guides` subtree copies.
6. Update badges, and add redirects from the legacy sites.

## Open decisions

- **Custom domain** (e.g. `docs.clima.caltech.edu`) vs
  `clima.github.io/clima/`. A custom domain lets the site move later to a
  host without the 1 GB limit (S3, Cloudflare) without breaking URLs.
- How many versions per package to publish. CloudMicrophysics at 37 MB per
  version is worth slimming.
- Verify that archiving a repo leaves its Pages site up before relying on
  frozen legacy sites.
