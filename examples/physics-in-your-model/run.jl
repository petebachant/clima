# Use CliMA physics (Thermodynamics, CloudMicrophysics, SurfaceFluxes) inside
# YOUR OWN model: no ClimaCore, no ClimaAtmos, just scalars and plain arrays.
#
# We build every parameter set from one ClimaParams TOML dictionary, in Float64
# and in Float32. On a small 8-level column of plain `Vector`s we then compute
# temperature, pressure and the cloud liquid/ice split from (ρ, e_int, q_tot),
# 1-moment rain autoconversion, accretion and fall speed, and bulk surface
# fluxes from the lowest level.
#
# Run from the repository root:
#     julia --project=examples/physics-in-your-model examples/physics-in-your-model/run.jl
# Runtime: about 15-30 s after precompilation, nearly all of it compilation;
# the physics itself runs in milliseconds.

import ClimaParams as CP
import Thermodynamics as TD
import CloudMicrophysics.Parameters as CMP
import CloudMicrophysics.Microphysics1M as CM1
import SurfaceFluxes as SF
import SurfaceFluxes.Parameters as SFP
import SurfaceFluxes.UniversalFunctions as UF
using Test

# 1. Parameters. Build them all from ONE TOML dictionary, so every package sees
# the same gravity, gas constants, latent heats and so on. The element type of
# the dictionary sets the precision of everything built from it. To calibrate or
# perturb a value, pass `override_file` (a path or a Dict) to `create_toml_dict`.
function build_params(::Type{FT}) where {FT}
    toml_dict = CP.create_toml_dict(FT)
    thp = TD.Parameters.ThermodynamicsParameters(toml_dict)
    mp = CMP.Microphysics1MParams(toml_dict)  # default 1-moment options
    sfp = SFP.SurfaceFluxesParameters(toml_dict, UF.BusingerParams)
    return (; thp, mp, sfp, toml_dict)
end

# 2. A pointwise "kernel", as it would sit in your own model's tendency loop. It
# takes parameter containers and scalars and returns scalars, so it broadcasts.
# Your model's prognostic state is (ρ, e_int, q_tot, q_rai). `saturation_adjustment`
# recovers T and the equilibrium liquid/ice split.
function column_kernel(thp, mp, ρ, e_int, q_tot, q_rai)
    (; T, q_liq, q_ice) = TD.saturation_adjustment(thp, TD.ρe(), ρ, e_int, q_tot)
    p = TD.air_pressure(thp, T, ρ, q_tot, q_liq, q_ice)
    # CloudMicrophysics takes the state as two NamedTuples. In it, cloud liquid
    # is `q_lcl` and cloud ice is `q_icl`.
    micro = (; q_tot, q_lcl = q_liq, q_icl = q_ice, q_rai, q_sno = zero(q_rai))
    thermo = (; ρ, T, w = zero(ρ))  # w: vertical velocity, used by Kessler autoconversion
    acnv = CM1.conv_q_lcl_to_q_rai(mp.processes.rain_autoconversion, mp, thp, micro, thermo)
    accr = CM1.accretion(mp.processes.cloud_liquid_rain_accretion, mp, thp, micro, thermo)
    v_rain = CM1.terminal_velocity(mp.precip.rain, mp.terminal_velocity.rain, ρ, q_rai)
    return (; T, p, q_liq, q_ice, acnv, accr, v_rain)
end

function run_column(::Type{FT}) where {FT}
    (; thp, mp, sfp, toml_dict) = build_params(FT)

    # --- Plain scalars: saturation over liquid and over ice at 263 K
    e_sat_liq = TD.saturation_vapor_pressure(thp, FT(263), TD.Liquid())
    e_sat_ice = TD.saturation_vapor_pressure(thp, FT(263), TD.Ice())

    # --- A synthetic 8-level column (use your model's own arrays here)
    z = FT[10, 500, 1000, 2000, 3000, 4000, 5000, 6000]           # height [m]
    T_true = @. FT(300) - FT(6.5e-3) * z                           # temperature [K]
    p_approx = @. FT(1e5) * exp(-z / FT(8000))                     # pressure [Pa]
    # Take ρ from the ideal gas law with vapor only, then set q_tot so the air is
    # sub-saturated up to 1 km and 5 % supersaturated (cloudy) above.
    ρ0 = TD.air_density.(thp, T_true, p_approx, FT(0.01))
    q_sat = TD.q_vap_saturation.(thp, T_true, ρ0)
    q_tot = @. ifelse(z > 1000, FT(1.05), FT(0.8)) * q_sat
    ρ = TD.air_density.(thp, T_true, p_approx, q_tot)
    # Equilibrium liquid/ice partition at the known T. Below freezing this puts
    # part of the condensate into ice.
    partition = TD.condensate_partition.(thp, T_true, ρ, q_tot)
    q_liq_true, q_ice_true = first.(partition), last.(partition)
    e_int = TD.internal_energy.(thp, T_true, q_tot, q_liq_true, q_ice_true)
    q_rai = fill(FT(5e-4), length(z))                              # some rain [kg/kg]

    # --- Broadcast the kernel down the column. A parameter struct acts as a
    # scalar in broadcasts. Wrapping it in `Ref(...)` also works.
    col = column_kernel.(thp, mp, ρ, e_int, q_tot, q_rai)
    T, q_liq, q_ice =
        getproperty.(col, :T), getproperty.(col, :q_liq), getproperty.(col, :q_ice)

    # --- Bulk surface fluxes over a warm, saturated sea surface, using level 1
    # (10 m) as the "interior" point
    T_sfc = FT(302)
    q_sfc = TD.q_vap_saturation(thp, T_sfc, ρ[1])
    config = SF.SurfaceFluxConfig(SF.ConstantRoughnessParams(toml_dict),
        SF.ConstantGustinessSpec(FT(1)))
    # Arguments are positional: air state, surface state, Φ_sfc, Δz, displacement
    # height d, air and surface winds, roughness_inputs (none here), config.
    fluxes(u) = SF.surface_fluxes(sfp, T[1], q_tot[1], q_liq[1], q_ice[1], ρ[1],
        T_sfc, q_sfc, zero(FT), z[1], zero(FT), (u, zero(FT)), (zero(FT), zero(FT)),
        nothing, config)
    winds = FT[2, 5, 10, 15]                                       # 10-m wind [m/s]
    sfc = fluxes.(winds)

    return (; z, T_true, q_liq_true, q_ice_true, T, q_liq, q_ice, col, q_tot, sfc, winds,
        e_sat_liq, e_sat_ice)
end

r64 = run_column(Float64)
r32 = run_column(Float32)

println(
    "  z [m]    T [K]    p [hPa]  q_liq [g/kg]  q_ice [g/kg]  autoconv [1/s]  accr [1/s]  v_rain [m/s]",
)
for (zk, c) in zip(r64.z, r64.col)
    println(lpad(Int(zk), 7), lpad(round(c.T; digits = 2), 9),
        lpad(round(c.p / 100; digits = 1), 10),
        lpad(round(1e3c.q_liq; digits = 3), 13), lpad(round(1e3c.q_ice; digits = 3), 13),
        lpad(round(c.acnv; sigdigits = 3), 15), lpad(round(c.accr; sigdigits = 3), 12),
        lpad(round(c.v_rain; digits = 2), 13))
end
for (u, s) in zip(r64.winds, r64.sfc)
    println(
        "U = $(u) m/s: SHF = $(round(s.shf; digits = 1)) W/m², LHF = $(round(s.lhf; digits = 1)) W/m², ",
        "u* = $(round(s.ustar; digits = 3)) m/s, ζ = $(round(s.ζ; digits = 3))")
end

@testset "physics-in-your-model" begin
    for (FT, r) in ((Float64, r64), (Float32, r32))
        @testset "$FT" begin
            # Types follow the parameter precision all the way through
            @test eltype(r.T) == FT && eltype(r.q_liq) == FT
            @test r.sfc[1].shf isa FT
            # Saturation over ice is lower than over liquid below freezing
            @test r.e_sat_ice < r.e_sat_liq
            # Saturation adjustment recovers the state we built (round trip)
            @test all(isapprox.(r.T, r.T_true; atol = 0.05))
            @test all(
                isapprox.(r.q_liq .+ r.q_ice, r.q_liq_true .+ r.q_ice_true; atol = 2e-5),
            )
            # Clear sky below 1 km, cloudy above, ice appears only when cold
            @test all(iszero, (r.q_liq .+ r.q_ice)[r.z .<= 1000])
            @test all(>(0), (r.q_liq .+ r.q_ice)[r.z .> 1000])
            @test all(iszero, r.q_ice[r.T .> 273.15])
            @test r.q_ice[end] > 0
            @test all(r.q_liq .+ r.q_ice .<= r.q_tot)
            # Pressure decreases with height
            @test issorted(getproperty.(r.col, :p); rev = true)
            # Microphysics rates are finite and non-negative. There is no
            # autoconversion without cloud liquid. Rain falls at a few m/s.
            acnv, accr = getproperty.(r.col, :acnv), getproperty.(r.col, :accr)
            @test all(isfinite, acnv) && all(>=(0), acnv) && all(>=(0), accr)
            @test all(iszero, accr[r.q_liq .== 0])
            @test maximum(accr) > 0
            @test all(v -> 1 < v < 10, getproperty.(r.col, :v_rain))
            # Warm, moist sea surface: upward heat fluxes, unstable (ζ < 0), and
            # the fluxes grow with wind speed
            @test all(s -> s.shf > 0 && s.lhf > 0 && s.ζ < 0 && isfinite(s.ustar), r.sfc)
            @test issorted(getproperty.(r.sfc, :ustar))
            @test issorted(getproperty.(r.sfc, :lhf))
        end
    end
    # Float32 and Float64 agree
    @test all(isapprox.(r32.T, r64.T; rtol = 1e-5))
    @test isapprox(r32.sfc[3].lhf, r64.sfc[3].lhf; rtol = 1e-3)
end
