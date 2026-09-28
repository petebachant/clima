# ClimaAtmos single-column simulation

You want to run a short ClimaAtmos single-column simulation and look at its output.

## What this example does

`run.jl` builds a single vertical column of atmosphere from a script (no YAML file).
It sets up the BOMEX shallow-cumulus case (Siebesma et al., 2003) on a coarse
30-level, 3 km grid and runs it for 10 simulated minutes. Instantaneous air
temperature (`ta`) and specific humidity (`hus`) are written as NetCDF to a
temporary directory. The script then reads them back with ClimaAnalysis and checks
that the profiles look like a warm, moist tropical boundary layer: finite values,
the expected shapes and output times, temperature and humidity that fall off with
height, and a column mass that stays nearly constant.

## Packages

- **ClimaAtmos** provides the model: `ColumnGrid`, `AtmosModel`, the `Setups.Bomex`
  case, the `Presets.equil_moist_0m` physics preset, `DiagnosticsConfig`,
  `AtmosSimulation`, and `solve_atmos!`.
- **ClimaAnalysis** reads the NetCDF diagnostics (`SimDir`, `get`, `slice`, `times`,
  `altitudes`).
- **Test** runs the checks at the end of the script.

## Run it

From the repository root:

```bash
julia --project=examples/atmos-single-column examples/atmos-single-column/run.jl
```

It takes about 2–4 minutes on a laptop CPU, almost all of it compilation. The
60 time steps themselves take under a second.

## Where to go next

- [Your first simulation](../../packages/ClimaAtmos/docs/src/first_simulation.md) and
  [Scripting simulations](../../packages/ClimaAtmos/docs/src/scripting_simulations.md):
  the script interface used here.
- [Running single-column cases](../../packages/ClimaAtmos/docs/src/single_column.md):
  DYCOMS, RICO, GABLS, TRMM, and the externally driven columns, plus the full
  YAML BOMEX configuration with the PROPHET/EDMF turbulence-convection scheme.
- [Computing and saving diagnostics](../../packages/ClimaAtmos/docs/src/diagnostics.md) and
  [Available diagnostics](../../packages/ClimaAtmos/docs/src/available_diagnostics.md).
- [Loading and visualizing output](../../packages/ClimaAtmos/docs/src/visualizing_output.md)
  and the [ClimaAnalysis docs](../../packages/ClimaAnalysis/docs/src/index.md):
  averaging, slicing, and plotting `OutputVar`s.
