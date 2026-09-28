# Calibrate a toy model

You want to calibrate a model's parameters against observations with
ClimaCalibrate, and see the whole workflow before pointing it at an expensive
climate model.

## What this example does

`run.jl` calibrates the growth rate `r` and carrying capacity `K` of a logistic
population model, `N(t) = K / (1 + (K/N0 - 1) e^{-rt})`. The observation is
generated from known values (`r = 0.5`, `K = 200`), and the prior is centred
well away from them. Eight ensemble members and five iterations of ensemble
Kalman inversion bring the ensemble mean from about `(0.32, 93)` to about
`(0.51, 213)`, and the data misfit falls by two orders of magnitude.

Along the way it shows the pieces every ClimaCalibrate calibration needs:

- a model interface, a subtype of `AbstractModelInterface` whose fields carry
  everything the model needs;
- `forward_model(interface, iteration, member)`, which reads the member's
  parameters from `parameter_path` and writes output under
  `path_to_ensemble_member`;
- `observation_map(interface, iteration)`, which collects the outputs into the
  G ensemble matrix, one column per member;
- a prior built with `constrained_gaussian` and `combine_distributions`;
- `calibrate` with the `JuliaBackend`, which runs members one after another.

All calibration files go to a temporary directory that is deleted at the end.
A final `@testset` checks that each parameter moved toward the truth, the
misfit fell, and the ensemble contracted.

## Packages

- **ClimaCalibrate** runs the calibration loop: it writes each member's
  parameters, runs the forward model on a backend, applies the observation map,
  checkpoints, and updates the ensemble.
- **EnsembleKalmanProcesses** provides the prior distributions and the ensemble
  Kalman inversion itself.
- **TOML** and **Random** (standard libraries) read the parameter files and seed
  the ensemble so the run is reproducible.

## Run it

From the repository root:

```bash
julia --project=examples/calibrate-toy-model examples/calibrate-toy-model/run.jl
```

It takes about 30 seconds on a laptop CPU, almost all of it compilation.

## Where to go next

- [ClimaCalibrate getting started](../../packages/ClimaCalibrate/docs/src/quickstart.md):
  the full interface, the output directory layout, and checkpointing.
- [Backends](../../packages/ClimaCalibrate/docs/src/backends.md): run the
  ensemble in parallel on Distributed workers or as HPC jobs.
- [Observations](../../packages/ClimaCalibrate/docs/src/observations.md):
  build observations and noise covariances from real data.
- [Troubleshooting](../../packages/ClimaCalibrate/docs/src/troubleshooting.md):
  when a calibration does not converge.
- [Calibration tutorial](../../packages/ClimaCalibrate/docs/literate_example.jl):
  a similar walkthrough with plots.
