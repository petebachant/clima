# # Single-column soil simulation with ClimaLand
#
# What this shows: how to build and run a short standalone ClimaLand
# simulation of one soil column, solving coupled soil water (Richards
# equation) and soil heat (`EnergyHydrology`). A steady rain rate and a
# steady ground heat flux enter through the top. The bottom is closed.
# We then check that the column's water and energy budgets close.
#
# Run from the repository root:
#
#     julia --project=examples/land-single-site examples/land-single-site/run.jl
#
# Runtime: about 30-60 s on a laptop CPU, almost all of it compilation.
# No artifacts are downloaded.

using Test
using ClimaLand
using ClimaLand.Soil
using ClimaLand.Domains: Column
import ClimaLand.Parameters as LP
import ClimaLand.Simulations: LandSimulation, solve!

# Use Float64 so that the conservation checks can be tight.
const FT = Float64
toml_dict = LP.create_toml_dict(FT)  # physical constants (ClimaParams)

# ## Soil parameters (a sandy loam)
# All values are in SI units. `hydrology_cm` is the van Genuchten water
# retention curve. The `ν_ss_*` values are volume fractions of the solids.
ν = FT(0.395)                      # porosity
params = Soil.EnergyHydrologyParameters(
    toml_dict;
    ν,
    ν_ss_om = FT(0.0),
    ν_ss_quartz = FT(0.92),
    ν_ss_gravel = FT(0.0),
    hydrology_cm = vanGenuchten{FT}(; α = FT(7.5), n = FT(1.89)),
    K_sat = FT(4.42 / 3600 / 100),  # saturated conductivity, m/s
    S_s = FT(1e-3),                 # specific storage, 1/m
    θ_r = FT(0.0),                  # residual water content
)

# ## Domain: a 1 m deep column with 20 layers
zmin, zmax = FT(-1), FT(0)
domain = Column(; zlim = (zmin, zmax), nelements = 20)

# ## Boundary conditions
# Fluxes are the upward (+z) component, so a negative top flux points into
# the soil. The functions take the cache `p` and time `t`.
rain = FT(-2e-7)       # m/s of liquid water, about 17 mm/day
ground_heat = FT(-20)  # W/m², heating the column from above
top = WaterHeatBC(;
    water = WaterFluxBC((p, t) -> rain),
    heat = HeatFluxBC((p, t) -> ground_heat),
)
bottom = WaterHeatBC(;
    water = WaterFluxBC((p, t) -> FT(0)),
    heat = HeatFluxBC((p, t) -> FT(0)),
)

soil = Soil.EnergyHydrology{FT}(;
    parameters = params,
    domain,
    boundary_conditions = (; top, bottom),
    sources = (),  # no phase change, no root extraction
)

# ## Initial conditions
# Uniform moisture (half of porosity) and temperature (15 °C), no ice.
# The prognostic energy variable is volumetric internal energy `ρe_int`,
# so we convert temperature using the soil heat capacity.
T0 = FT(288.15)
function set_ic!(Y, p, t0, model)
    ps = model.parameters
    Y.soil.ϑ_l .= FT(0.5) * ps.ν
    Y.soil.θ_i .= FT(0)
    θ_l = Soil.volumetric_liquid_fraction.(Y.soil.ϑ_l, ps.ν, ps.θ_r)
    ρc_s = Soil.volumetric_heat_capacity.(
        θ_l,
        Y.soil.θ_i,
        ps.ρc_ds,
        ps.earth_param_set,
    )
    Y.soil.ρe_int .=
        Soil.volumetric_internal_energy.(Y.soil.θ_i, ρc_s, T0, ps.earth_param_set)
end

# ## Build and run the simulation: 2 days with a 30 minute step
# The default timestepper is implicit-explicit (IMEX), so a long step is
# stable. `diagnostics = ()` turns off NetCDF output. We save the state
# every 6 hours.
t0, tf, dt = 0.0, 2 * 86400.0, 1800.0
simulation = LandSimulation(
    t0,
    tf,
    dt,
    soil;
    set_ic!,
    diagnostics = (),
    solver_kwargs = (; saveat = 6 * 3600.0),
)
sol = solve!(simulation)

# ## Look at the results
# `sol.u[k].soil` holds the prognostic state at saved time `k`. Summing a
# ClimaCore `Field` over a column integrates it in z, which gives the
# column total per unit area.
column_water(Y) = sum(Y.soil.ϑ_l)    # m³ water per m² ground (= m)
column_energy(Y) = sum(Y.soil.ρe_int)  # J/m²
W = column_water.(sol.u)
E = column_energy.(sol.u)
elapsed = FT(tf - t0)
ϑ_end = vec(parent(sol.u[end].soil.ϑ_l))
T_end = vec(parent(simulation._integrator.p.soil.T))  # diagnosed temperature

println("Column water: $(W[1]) -> $(W[end]) m")
println("Column energy: $(E[1]) -> $(E[end]) J/m²")
println("Surface/bottom ϑ_l at end: $(last(ϑ_end)), $(first(ϑ_end))")
println("Surface/bottom T at end:   $(last(T_end)), $(first(T_end)) K")

@testset "land-single-site: soil column" begin
    # One saved state every 6 hours over 2 days, including t0
    @test length(sol.u) == 9
    @test length(ϑ_end) == 20

    # Finite, physically bounded state
    @test all(isfinite, ϑ_end) && all(isfinite, T_end)
    @test all(0 .< ϑ_end .<= ν)
    @test all(270 .< T_end .< 310)

    # Rain wets the column, so column water grows monotonically. With a
    # closed bottom, gravity drains water down: the bottom layer ends up
    # wetter than the top, and both wetter than at the start.
    ϑ_start = FT(0.5) * ν
    @test all(diff(W) .> 0)
    @test first(ϑ_end) > last(ϑ_end) > ϑ_start
    # Heating from above: the surface warms, the bottom is still near T0.
    @test last(T_end) > T0
    @test abs(first(T_end) - T0) < 0.5

    # Conservation: the change in column totals equals the net boundary
    # flux times elapsed time (bottom fluxes are zero).
    @test W[end] - W[1] ≈ -rain * elapsed rtol = 1e-6
    @test E[end] - E[1] ≈ -ground_heat * elapsed rtol = 1e-6
    # The model also integrates its boundary fluxes in time, as extra
    # prognostic variables. They should agree with the storage change.
    ∫F_water(Y) = only(parent(Y.soil.∫F_vol_liq_water_dt))
    ∫F_energy(Y) = only(parent(Y.soil.∫F_e_dt))
    @test W[end] - W[1] ≈ ∫F_water(sol.u[end]) - ∫F_water(sol.u[1]) rtol = 1e-6
    @test E[end] - E[1] ≈ ∫F_energy(sol.u[end]) - ∫F_energy(sol.u[1]) rtol = 1e-6
end
