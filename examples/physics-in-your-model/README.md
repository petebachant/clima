# Physics in your model

You want to use CliMA's physics (moist thermodynamics, cloud microphysics and
surface fluxes) in your own model, without adopting ClimaAtmos or ClimaCore.

## What this example does

[`run.jl`](run.jl) runs a small synthetic 8-level atmospheric column held in plain
Julia `Vector`s. It runs the whole thing in both `Float64` and `Float32`:

1. **Parameters.** It builds one ClimaParams TOML dictionary and constructs the
   parameter containers of all three packages from it, so they share the same
   physical constants.
2. **Thermodynamics.** It computes saturation vapor pressure over liquid and ice
   from plain scalars. On the column it goes from the prognostic variables
   `(ρ, e_int, q_tot)` to temperature and pressure, and splits the condensate into
   liquid and ice with `saturation_adjustment`.
3. **CloudMicrophysics.** It computes 1-moment rain autoconversion, accretion of
   cloud liquid by rain, and the rain terminal velocity.
4. **SurfaceFluxes.** It computes bulk Monin-Obukhov fluxes (sensible and latent
   heat, friction velocity) over a warm sea surface for several wind speeds.

The physics sits in one pointwise function, `column_kernel`, which takes parameter
containers and scalars. The script applies it to arrays by broadcasting
(`column_kernel.(thp, mp, ρ, e_int, q_tot, q_rai)`). The same pattern works in a
loop, a GPU kernel or a `ClimaCore` field broadcast. A `@testset` at the end
checks round-trip consistency, physical signs and monotonicity, and agreement
between Float32 and Float64.

## Packages used

| Package | Why |
|---|---|
| [ClimaParams](../../packages/ClimaParams) | One source of parameter values. Change it (or calibrate it) with `override_file`. |
| [Thermodynamics](../../packages/Thermodynamics) | Moist-air equation of state, energies, saturation, phase equilibrium |
| [CloudMicrophysics](../../packages/CloudMicrophysics) | Process rates for rain and snow (1-moment scheme here) |
| [SurfaceFluxes](../../packages/SurfaceFluxes) | Monin-Obukhov surface-layer fluxes |

Always pass the parameter containers (`thp`, `mp`, `sfp`) to the physics
functions. Never copy constants into your code: with containers, a single
override reaches every package consistently.

## Run it

From the repository root:

```bash
julia --project=examples/physics-in-your-model examples/physics-in-your-model/run.jl
```

After precompilation this takes about 15-30 s, almost all of it compilation.

## Where to go next

- Thermodynamics [How-To Guide](../../packages/Thermodynamics/docs/src/HowToGuide.md),
  which covers formulations, saturation adjustment options, GPU use and AD.
- CloudMicrophysics [1-moment scheme](../../packages/CloudMicrophysics/docs/src/Microphysics1M.md),
  [terminal velocity](../../packages/CloudMicrophysics/docs/src/TerminalVelocity.md) and
  [bulk tendencies](../../packages/CloudMicrophysics/docs/src/BulkTendencies.md), which
  gives all process tendencies in one call.
- SurfaceFluxes [quick start](../../packages/SurfaceFluxes/docs/src/index.md) and
  [theory](../../packages/SurfaceFluxes/docs/src/SurfaceFluxes.md), which covers
  roughness, gustiness and roughness-sublayer options.
- ClimaParams [parameter retrieval and overrides](../../packages/ClimaParams/docs/src/param_retrieval.md)
  and [calibration](../../packages/ClimaParams/docs/src/calibration.md).
