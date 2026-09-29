# Add your own closure to ClimaAtmos and calibrate it

You want to add your own physics to ClimaAtmos and calibrate it.

## The extension point

A vertical-diffusion closure in ClimaAtmos is a subtype of
`ClimaAtmos.AbstractVerticalDiffusion` with one method of
`ClimaAtmos.ᶜeddy_diffusivity(Y, p, closure)`, which returns the cell-center
eddy diffusivity. The vertical diffusion tendency, the implicit solver's
Jacobian and the `edt`/`evu` diagnostics all get the diffusivity from that one
function. So once you have written it, `AtmosModel(grid; vertical_diffusion = MyClosure(...))`
gives you heat and momentum diffusion, harmonic-mean face values and implicit
time stepping without editing ClimaAtmos. The method can read the current
state `Y` and the cache `p`, including the surface friction velocity and
Obukhov length in `p.precomputed.sfc_conditions`.

## What this example does

The workflow follows Shin, Kale & Howland ([arXiv:2604.19500](https://arxiv.org/abs/2604.19500)),
who calibrate the YSU K-profile boundary-layer scheme in idealized dry
single-column cases.

1. **Add the physics.** `run.jl` defines a K-profile closure (Troen–Mahrt / YSU family),

       K(z) = K_bg + κ u* z (1 − z/h)^p / φ_h(z/L)   (the second term only below h)

   with φ_h = 1 + β z/L in stable conditions and a stable boundary-layer height
   h = c_h √(u* L / f) (Zilitinkevich), capped at the domain top. It has three
   calibrated parameters: the shape exponent `p` (YSU uses 2), the height
   coefficient `c_h`, and the stability slope `β`. It guards against L → 0,
   L < 0 and h → 0.
2. **Forward model and synthetic observations.** It runs the GABLS stable
   boundary layer (Beare et al., 2006): dry, 40 levels to 400 m, 3 simulated
   hours, with diffusion treated implicitly. It averages θ, wind speed and wind
   direction over the last hour at 5 heights up to about the boundary-layer
   height, and adds Gaussian noise. As in the paper, this is a perfect-model
   test: the observations come from the same model with known "true" parameters.
3. **Sensitivity and observation selection.** It perturbs each parameter by ±20%,
   one at a time, and prints |Δobservation| / σ_noise. Only observations that
   some parameter moves by more than the noise are kept. With the defaults, 14
   of the 15 are kept (only the 25 m wind speed is dropped), and every parameter
   has informative observations.
4. **Calibration.** Ensemble Kalman inversion with ClimaCalibrate
   (`JuliaBackend`, 10 members, 5 iterations), starting from priors centred away
   from the truth. The ensemble mean goes from (p, c_h, β) ≈ (1.31, 0.51, 2.99)
   to (1.89, 0.41, 4.81); the truth is (2, 0.4, 5). The misfit falls from 64 to 5.

The closing `@testset` checks that the closure changes the solution, that K is
finite, non-negative and equal to K_bg above h, that the truth run is stably
stratified, that each parameter has an informative observation, and that EKI
lowers the misfit, moves every parameter toward the truth and contracts the
ensemble.

What we simplified compared with the paper:

- **EKI instead of emulate-and-sample.** The paper trains Gaussian-process
  emulators and samples the posterior with MCMC. EKI gives a point estimate,
  with ensemble spread only as a rough uncertainty measure.
- **One case instead of two.** This example has only the stable case, no
  convective boundary layer.
- **A cruder sensitivity analysis.** It uses one-at-a-time finite differences
  in place of a global sensitivity analysis.
- **A short, coarse run.** It uses 3 hours instead of the quasi-steady state
  GABLS reaches after about 8 hours.

## Packages

- **ClimaAtmos**: the model, the `AbstractVerticalDiffusion` / `ᶜeddy_diffusivity`
  extension point, the `Setups.GABLS` case, diagnostics and `solve_atmos!`.
- **ClimaCore**: `Fields` utilities to get heights inside the closure.
- **ClimaAnalysis**: reads the time-averaged NetCDF diagnostics.
- **ClimaCalibrate** and **EnsembleKalmanProcesses**: the calibration loop,
  priors and EKI.
- **LinearAlgebra**, **Random**, **TOML**, **Test**: the noise covariance, a seeded
  RNG, parameter files and the checks.

## Run it

From the repository root:

```bash
julia --project=examples/atmos-custom-closure-calibration examples/atmos-custom-closure-calibration/run.jl
```

It takes about 3.5 minutes on one laptop CPU core. About 2.5 minutes of that is
compilation. Each 3-hour simulation then takes about 1 second, and the script
runs 60 of them. It prints a warning each time a model is built, because the
example overrides the GABLS surface humidity to run dry.

## Where to go next

- **Add the convective case.** The paper's second case is a convective
  boundary layer. It needs a boundary-layer height for unstable conditions,
  such as a bulk Richardson number, and the unstable branch of φ_h, which the
  closure already has. See
  [Running single-column cases](../../packages/ClimaAtmos/docs/src/single_column.md)
  for the available setups.
- **Get a posterior.** For the paper's full emulate-and-sample posterior, feed the
  EKI ensemble into [CalibrateEmulateSample.jl](https://github.com/CliMA/CalibrateEmulateSample.jl),
  which trains an emulator on the ensemble's input and output pairs and runs
  MCMC on it.
- **Run real ensembles.** For expensive members, switch `JuliaBackend` to a
  parallel or HPC backend; see
  [ClimaCalibrate backends](../../packages/ClimaCalibrate/docs/src/backends.md)
  and [how a calibration works](../../packages/ClimaCalibrate/docs/src/concepts.md).
- **Read more about diffusion in ClimaAtmos.**
  [Diffusion in ClimaAtmos](../../packages/ClimaAtmos/docs/src/diffusion.md)
  covers the vertical-diffusion formulation and the "Adding your own closure"
  hook. [Scripting simulations](../../packages/ClimaAtmos/docs/src/scripting_simulations.md)
  and [Computing and saving diagnostics](../../packages/ClimaAtmos/docs/src/diagnostics.md)
  cover the script interface used here.
- **Start with something simpler.** [Calibrate a toy model](../calibrate-toy-model/)
  shows the same ClimaCalibrate loop on a model that runs in microseconds.
