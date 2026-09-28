# Build your own model on ClimaCore

You want to write your own PDE model, a column physics scheme or a toy
testbed, on the same spatial discretization and time steppers that
ClimaAtmos and ClimaLand use.

## What this example does

[`run.jl`](run.jl) builds a small model from scratch: heat diffusion,
`∂T/∂t = ∇·(K(z) ∇T)`, in an insulated 1 m column.

1. It picks the compute device and communication context explicitly with
   ClimaComms, then builds domain -> mesh (exponentially stretched) ->
   topology -> center and face spaces.
2. It puts a temperature `Field` on cell centers, with a warm layer on a
   280 K background. The field is wrapped in a `FieldVector` state, and a
   depth-dependent diffusivity lives on cell faces in the cache `p`.
3. The tendency is one fused broadcast of the staggered finite-difference
   operators `GradientC2F` (centers to faces) and `DivergenceF2C` (faces to
   centers). Zero-flux boundaries come from `SetValue` on the divergence.
4. It integrates with ClimaTimeSteppers' explicit SSP Runge-Kutta scheme:
   `ClimaODEFunction`, then `ODEProblem`, then `solve`.
5. A `@testset` checks that the tendency integrates to zero, total heat
   `sum(Y.T)` is conserved to round-off, the variance falls monotonically,
   the maximum principle holds, and every value is finite.

## Packages

- **ClimaComms** picks the device (CPU or GPU) and the context (single
  process or MPI). If you pass them in explicitly, the same script runs on a
  GPU with `CLIMACOMMS_DEVICE=CUDA`.
- **ClimaCore** provides the grid, the fields, the operators and their
  boundary conditions.
- **ClimaTimeSteppers** advances ClimaCore fields in time with explicit,
  IMEX and Rosenbrock methods.

## Run it

From the repository root:

```bash
julia --project=examples/build-on-climacore examples/build-on-climacore/run.jl
```

It takes about 10-30 s on a laptop CPU once packages are precompiled, and it
writes no files.

## Where to go next

- ClimaCore concepts (domain, mesh, space, field, operator):
  [concepts.md](../../packages/ClimaCore/docs/src/getting_started/concepts.md)
- Boundary conditions on the finite-difference operators:
  [boundary_conditions.md](../../packages/ClimaCore/docs/src/howto/boundary_conditions.md)
  and [operators_fd.md](../../packages/ClimaCore/docs/src/reference/operators_fd.md)
- Dirichlet boundaries and comparison with an analytic solution:
  [column_heat.jl tutorial](../../packages/ClimaCore/docs/tutorials/column_heat.jl)
  and [examples/column/heat.jl](../../packages/ClimaCore/examples/column/heat.jl)
- Time stepping with ClimaCore, including implicit vertical diffusion:
  [timestepping.md](../../packages/ClimaCore/docs/src/howto/timestepping.md)
  and the ClimaTimeSteppers
  [diffusion tutorial](../../packages/ClimaTimeSteppers/docs/src/tutorials/diffusion.md)
- Running on a GPU:
  [run_on_gpu.md](../../packages/ClimaCore/docs/src/howto/run_on_gpu.md);
  device and context:
  [ClimaComms getting started](../../packages/ClimaComms/docs/src/getting_started.md)
