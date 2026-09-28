# AGENTS.md

Instructions for AI agents (and humans) working in the CliMA monorepo.

## Read first

1. [README.md](README.md): layout, and the command for every common task.
2. [docs/dev/AGENTS.md](docs/dev/AGENTS.md): shared CliMA engineering
   standards (architecture, GPU performance, testing, code style).
3. `packages/<Pkg>/AGENTS.md`, if it exists: package-specific guidance.
   Where it says `docs/dev-guides/`, read `docs/dev/` at the repo root
   instead. The per-package copies are leftovers from the standalone repos.

## Rules specific to the monorepo

- **Environments.** Use `julia --project=packages/<Pkg>` (Julia 1.12+). The
  root workspace makes every in-repo package resolve to its path. Don't run
  `Pkg.develop` on in-repo packages and don't commit `Manifest.toml`.
- **Scope of testing.** Before finishing a change, run
  `julia tools/mono.jl affected main` and run the tests for every package it
  lists. A change is not done if a downstream package breaks.
- **Compat.** `julia tools/mono.jl compat` must report no drift. If you make
  a breaking change, use `julia tools/mono.jl bump <Pkg> <level>` rather than
  editing versions by hand. It widens dependents' compat for you.
- **Releases.** Bumping `version` in a `Project.toml` *is* a release once
  merged. Only do it when asked, and update that package's `NEWS.md`.
- **Workspace file.** `Project.toml` at the root is generated; edit
  `packages.toml` and run `julia tools/mono.jl workspace`.
- **Upstream sync.** During the evaluation, don't edit `docs/dev/`
  expecting it to stick. Changes there belong in CliMA/DeveloperGuides
  until the monorepo becomes the source of truth.
