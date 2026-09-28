# Single-column soil simulation

You want to run a short standalone ClimaLand simulation at a single site.

## What this example does

`run.jl` builds a 1 m deep soil column with 20 layers. It solves coupled soil
water (Richards equation) and soil heat with `ClimaLand.Soil.EnergyHydrology`.
A steady rain rate and a steady ground heat flux enter through the top, and the
bottom is closed. It runs for 2 days with a 30-minute implicit-explicit
timestep, using `ClimaLand.Simulations.LandSimulation`.

At the end it checks that:

- moisture and temperature are finite and physically bounded;
- column water grows monotonically and drains toward the closed bottom;
- the surface warms;
- the change in column water and energy equals the boundary flux times the
  elapsed time, to a relative error of 1e-6. The model's own time-integrated
  boundary fluxes (`∫F_vol_liq_water_dt`, `∫F_e_dt`) agree too.

No artifacts are downloaded, and no output files are written.

## Packages used

- **ClimaLand**: soil model, column domain, boundary conditions, and the
  `LandSimulation` driver. It pulls in ClimaParams (physical constants, via
  `ClimaLand.Parameters.create_toml_dict`), ClimaCore (the column grid and
  `Field`s), and ClimaTimeSteppers (the default IMEX timestepper). The script
  never has to import them directly.
- **Test**: the closing `@testset`.

## How to run

From the repository root:

```sh
julia --project=examples/land-single-site examples/land-single-site/run.jl
```

A run takes about 30-60 s, almost all of it compilation.

## Where to go next

- [Richards equation tutorial](../../packages/ClimaLand/docs/src/tutorials/standalone/Soil/richards_equation.jl):
  water only, reaching hydrostatic equilibrium.
- [Soil energy and hydrology tutorial](../../packages/ClimaLand/docs/src/tutorials/standalone/Soil/soil_energy_hydrology.jl)
- [Soil boundary conditions](../../packages/ClimaLand/docs/src/tutorials/standalone/Soil/boundary_conditions.jl):
  atmosphere-driven and other boundary conditions.
- [Bucket model tutorial](../../packages/ClimaLand/docs/src/tutorials/standalone/Bucket/bucket_tutorial.jl):
  a simpler land model.
- [Single-column land surface tutorial](../../packages/ClimaLand/docs/src/tutorials/standalone/Usage/LSM_single_column_tutorial.jl):
  soil coupled with other components.
- [`LandSimulation` API](../../packages/ClimaLand/docs/src/APIs/Simulations.md)
  and [ClimaLand getting started](../../packages/ClimaLand/docs/src/getting_started.md)
