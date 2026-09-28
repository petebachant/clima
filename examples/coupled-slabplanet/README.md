# Coupled slabplanet

You want to run a coupled climate simulation: an atmosphere talking to land and ocean.

## What this example does

`run.jl` runs the smallest global coupled setup that ClimaCoupler supports, the
"slabplanet": a ClimaAtmos atmosphere on a coarse cubed sphere (2x2 elements per
face, 10 levels, gray radiation), a ClimaLand bucket model on the continents, and
a thermal slab ocean everywhere else. It starts from the `slabplanet_default.yml`
config that ships with ClimaCoupler, shrinks it, and runs 5 coupling steps of
200 s. It then checks that land and ocean tile the sphere, that surface
temperatures and turbulent fluxes are finite and plausible, that the slab ocean
evolved, and that global energy and water are conserved.

## Packages

- **ClimaCoupler**: builds the coupled simulation from a config dictionary, exchanges
  fields between components, computes surface fluxes, and checks conservation.
- **ClimaAtmos**: the atmosphere. Loading it activates ClimaCoupler's atmosphere extension.
- **ClimaLand**: the bucket land model. Loading it activates ClimaCoupler's land extension.
- **ClimaComms**: selects the CPU backend.
- **ClimaCore**: needed only for a temporary workaround (see below).

## How to run

From the repository root:

```bash
julia --project=examples/coupled-slabplanet examples/coupled-slabplanet/run.jl
```

This is heavy for an example. Expect about 3.5 minutes on one CPU thread (after
precompilation), nearly all of it compiling. Peak memory is about 5 GB. The first
run downloads a small (<1 MB) land-sea mask artifact.

Two workarounds for bugs at HEAD are marked `WORKAROUND` in `run.jl`. One is a
missing `ClimaCore.Spaces.issubspace` method that breaks every global coupled
run. The other is an unassigned `output_writer` when bucket land diagnostics are
turned off.

## Where to go next

- [Running a simulation](../../packages/ClimaCoupler/docs/src/running.md): config files, the REPL, and `step!`
- [Simulation types](../../packages/ClimaCoupler/docs/src/simtypes.md): `slabplanet`, `amip`, `cmip`, and single-column modes
- [Input options](../../packages/ClimaCoupler/docs/src/input.md) and ready-made configs in [`config/ci_configs`](../../packages/ClimaCoupler/config/ci_configs)
- [Conservation checks](../../packages/ClimaCoupler/docs/src/conservation.md)
- [ClimaAtmos global simulations](../../packages/ClimaAtmos/docs/src/global_simulations.md)
- [ClimaLand getting started](../../packages/ClimaLand/docs/src/getting_started.md)
