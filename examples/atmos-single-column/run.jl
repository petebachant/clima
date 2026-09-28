# # A short ClimaAtmos single-column simulation (BOMEX)
#
# This example builds a single-column atmosphere from a script, runs the BOMEX
# shallow-cumulus case (Siebesma et al., 2003) for a few simulated minutes,
# writes NetCDF diagnostics, and reads one of them back with ClimaAnalysis.
#
# Run it from the repository root with
#
#     julia --project=examples/atmos-single-column examples/atmos-single-column/run.jl
#
# Expect a few minutes of wall-clock time on a laptop CPU, almost all of it
# compilation; the simulation itself takes seconds.

import ClimaAtmos as CA
import ClimaAnalysis
using Test

const FT = Float64

# ## 1. The model: grid + parameters + case setup + physics
#
# A `ColumnGrid` is a single vertical column. We use 30 uniform levels over the
# lowest 3 km (100 m spacing), which covers BOMEX's cloud layer (~0.5–2 km).
grid = CA.ColumnGrid(FT; z_elem = 30, z_max = 3000.0, z_stretch = false)

# `ClimaAtmosParameters` gathers the physical constants (from ClimaParams).
params = CA.ClimaAtmosParameters(FT)

# The *setup* supplies the case: BOMEX's initial profiles, surface fluxes,
# subsidence, and large-scale forcing. The *preset* supplies the physics the
# case needs; BOMEX is moist, so we use equilibrium moisture with 0-moment
# microphysics (instantly remove any excess condensate as precipitation).
model = CA.AtmosModel(
    grid;
    params,
    setup = CA.Setups.Bomex(; thermo_params = params.thermodynamics_params),
    defaults = CA.Presets.equil_moist_0m(),
)

# ## 2. The simulation: timestep, duration, and output
#
# We run 10 minutes with a 10 s timestep. Diagnostics are written as NetCDF to
# a temporary directory: instantaneous air temperature (`ta`) and specific
# humidity (`hus`) every 5 minutes. `default = false` skips the (larger)
# built-in diagnostic set.
output_dir = mktempdir()
t_end = 600.0
diagnostics = CA.DiagnosticsConfig(;
    default = false,
    additional = (
        "ta" => (; period = "5mins", reduction = "inst"),
        "hus" => (; period = "5mins", reduction = "inst"),
    ),
)
simulation =
    CA.AtmosSimulation(model; dt = 10, t_end, output_dir, diagnostics)

# The prognostic state `Y` exists before we run: cell-center variables live in
# `Y.c` (density ρ, total energy ρe_tot, total water ρq_tot, ...) and
# cell-face variables in `Y.f` (vertical velocity u₃).
Y = simulation.integrator.u
ρ_column_initial = sum(Y.c.ρ)  # column-integrated air mass per unit area [kg/m²]

# ## 3. Run
CA.solve_atmos!(simulation)
ρ_column_final = sum(Y.c.ρ)

# ## 4. Read the output back with ClimaAnalysis
#
# `SimDir` catalogs every diagnostic file in the output directory, and `get`
# returns one as an `OutputVar`: an array plus its dimensions and attributes.
simdir = ClimaAnalysis.SimDir(simulation.output_dir)
ta = get(simdir; short_name = "ta", reduction = "inst", period = "5m")
hus = get(simdir; short_name = "hus", reduction = "inst", period = "5m")

t = ClimaAnalysis.times(ta)      # output times [s]
z = ClimaAnalysis.altitudes(ta)  # model-level heights [m]
println("ta dimensions: ", collect(keys(ta.dims)), ", size ", size(ta.data))
println("output times [s]: ", t)

# A column's output has dimensions (time, z). Slicing at the last output time
# leaves a vertical profile.
ta_profile = ClimaAnalysis.slice(ta; time = last(t)).data
hus_profile = ClimaAnalysis.slice(hus; time = last(t)).data
println("surface-layer T = ", round(first(ta_profile); digits = 2), " K, ",
    "T at 3 km = ", round(last(ta_profile); digits = 2), " K")

# ## 5. Checks
@testset "BOMEX single column" begin
    # The run reached the requested end time and the state is finite.
    # (`integrator.t` is an exact integer time type; `float` converts to seconds.)
    @test float(simulation.integrator.t) ≈ t_end
    @test all(isfinite, parent(Y.c.ρ))
    @test all(isfinite, parent(Y.c.ρe_tot))

    # Output at t = 0, 5, 10 min on all 30 model levels.
    @test t ≈ [0.0, 300.0, 600.0]
    @test size(ta.data) == (3, 30)
    @test length(z) == 30
    @test issorted(z) && 0 < first(z) < last(z) < 3000

    # BOMEX is a warm tropical marine boundary layer: ~299–300 K near the
    # surface, cooling with height, and moist air (hus ~17 g/kg) that dries aloft.
    @test all(isfinite, ta.data) && all(isfinite, hus.data)
    @test 295 < first(ta_profile) < 302
    @test all(270 .< ta_profile .< 305)
    @test last(ta_profile) < first(ta_profile) - 10       # T decreases with height
    @test 0.014 < first(hus_profile) < 0.020
    @test all(0 .<= hus_profile .< 0.025)
    @test last(hus_profile) < first(hus_profile) / 2      # drier aloft

    # Ten minutes is far too short to move the column much away from the
    # prescribed BOMEX initial state.
    @test maximum(abs, ta.data[end, :] .- ta.data[1, :]) < 1
    # Column air mass changes only through surface moisture fluxes (tiny here).
    @test isapprox(ρ_column_final, ρ_column_initial; rtol = 1e-4)
end
