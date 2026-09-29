# # Add your own boundary-layer closure to ClimaAtmos, then calibrate it
#
# This example (inspired by Shin, Kale & Howland, arXiv:2604.19500):
#   1. adds a K-profile boundary-layer closure (Troen–Mahrt / YSU family) to
#      ClimaAtmos without editing ClimaAtmos;
#   2. runs it on the GABLS stable boundary layer and makes synthetic
#      "perfect-model" observations of time-averaged θ, wind speed and wind
#      direction at 5 heights;
#   3. checks which observations are sensitive to which parameter;
#   4. recovers the closure's parameters with ClimaCalibrate + EKI.
#
# Run it from the repository root with
#
#     julia --project=examples/atmos-custom-closure-calibration examples/atmos-custom-closure-calibration/run.jl
#
# It takes about 3.5 minutes on one laptop CPU core: ~2.5 minutes of compilation,
# then ~1 s per 3-hour simulation for the 60 simulations it runs.

import ClimaAtmos as CA
import ClimaCore: Fields
import ClimaAnalysis
import ClimaCalibrate as CAL
import EnsembleKalmanProcesses as EKP
import EnsembleKalmanProcesses.ParameterDistributions:
    combine_distributions, constrained_gaussian
import LinearAlgebra: Diagonal
import Random, TOML
using Test

const FT = Float64

# ## 1. The closure: K(z) = K_bg + κ u* z (1 - z/h)^p / φ_h(z/L)   for z < h
#
# A closure is a subtype of `CA.AbstractVerticalDiffusion` plus one method of
# `CA.ᶜeddy_diffusivity`. ClimaAtmos uses the returned diffusivity for heat and
# momentum, in the tendency and in the implicit solver's Jacobian.
Base.@kwdef struct KProfile{FT} <: CA.AbstractVerticalDiffusion
    p::FT = 2.0          # shape exponent (YSU uses 2)             [calibrated]
    c_h::FT = 0.4        # boundary-layer height coefficient       [calibrated]
    β::FT = 5.0          # stable-stability slope, φ_h = 1 + β z/L [calibrated]
    f::FT = 1.39e-4      # Coriolis parameter [1/s] (GABLS)
    h_max::FT = 400.0    # cap on h: the domain top [m]
    K_bg::FT = 0.01      # background diffusivity, also above h [m²/s]
    κ::FT = 0.4          # von Kármán constant
end
Base.broadcastable(c::KProfile) = tuple(c)  # broadcast the struct as a scalar

# Stable-BL height (Zilitinkevich): h = c_h √(u* L / f). For L ≤ 0 (neutral or
# unstable) this scaling does not apply, so we fall back to the cap; a
# convective case would need e.g. a bulk-Richardson-number diagnostic instead.
function bl_height(c, ustar, L)
    h = ifelse(L > 0, c.c_h * sqrt(ustar * max(L, eps(L)) / c.f), c.h_max)
    return clamp(h, oftype(h, 10), c.h_max)  # keep h ≥ 10 m so z/h stays finite
end

function k_profile(c, ustar, L, z)
    h = bl_height(c, ustar, L)
    ζ = z / ifelse(L ≥ 0, max(L, one(L)), min(L, -one(L)))  # guard L → 0
    φ_h = ifelse(ζ ≥ 0, 1 + c.β * ζ, 1 / sqrt(1 - 16 * min(ζ, 0)))  # Businger–Dyer
    return c.K_bg + c.κ * ustar * z * max(1 - z / h, 0)^c.p / φ_h
end

# The hook. u* and L live on the surface (a single horizontal level); a
# pointwise broadcast against the 3D height field pairs each column with its
# own surface values, so this also works on the sphere. (Returning a plain `@.`
# broadcast allocates a Field per call; ClimaAtmos's own closures return
# `LazyBroadcast.lazy` broadcasts to avoid that, which matters on GPUs.)
function CA.ᶜeddy_diffusivity(Y, p, c::KProfile)
    (; ustar, obukhov_length) = p.precomputed.sfc_conditions
    ᶜz = Fields.coordinate_field(Y.c).z
    z_sfc = Fields.level(Fields.coordinate_field(Y.f).z, Fields.half)
    return @. k_profile(c, ustar, obukhov_length, ᶜz - z_sfc)
end

# ## 2. The forward model: GABLS for 3 h, observations averaged over the last hour
const z_obs = [25.0, 65.0, 105.0, 145.0, 185.0]  # cell centres up to about h [m]

function run_gabls(closure; output_dir = mktempdir(), diff_mode = CA.Implicit())
    grid = CA.ColumnGrid(FT; z_elem = 40, z_max = 400.0, z_stretch = false)
    params = CA.ClimaAtmosParameters(FT)
    model = CA.AtmosModel(grid; params,
        setup = CA.Setups.GABLS(;
            prognostic_tke = false, thermo_params = params.thermodynamics_params,
        ),
        defaults = CA.Presets.dry(),
        vertical_diffusion = closure,
        diff_mode,  # implicit by default: explicit K-profile diffusion is unstable at dt = 10 s
        # WORKAROUND: GABLS sets a surface humidity (q_vap = 0), which a dry
        # model rejects; clearing it here triggers a harmless override warning.
        boundary_overrides = CA.SurfaceConditions.SurfaceBoundaryOverrides(),
    )
    avg = (; period = "1hours", reduction = "average")
    diagnostics = CA.DiagnosticsConfig(;
        default = false, additional = ("thetaa" => avg, "ua" => avg, "va" => avg),
    )
    simulation = CA.AtmosSimulation(model; dt = 10, t_end = "3hours", output_dir,
        diagnostics, callback_kwargs = (; log_progress = false))
    CA.solve_atmos!(simulation)
    simdir = ClimaAnalysis.SimDir(simulation.output_dir)
    last_hour(name) =
        let v = get(simdir; short_name = name, reduction = "average")
            ClimaAnalysis.slice(v; time = last(ClimaAnalysis.times(v))).data
        end
    θ, u, v = last_hour("thetaa"), last_hour("ua"), last_hour("va")
    z = ClimaAnalysis.altitudes(get(simdir; short_name = "ua", reduction = "average"))
    k = [argmin(abs.(z .- zo)) for zo in z_obs]
    # Observation vector: [θ (K); wind speed (m/s); wind direction (degrees)]
    obs = [θ[k]; hypot.(u[k], v[k]); atand.(v[k], u[k])]
    return (; obs, θ, simulation)
end

# ## 3. Truth run and synthetic observations (a perfect-model experiment)
truth = KProfile{FT}()
param_names = ["p", "c_h", "β"]
ϕ_true = [truth.p, truth.c_h, truth.β]
closure(ϕ) = KProfile{FT}(; p = ϕ[1], c_h = ϕ[2], β = ϕ[3])
truth_run = run_gabls(truth)  # the first run also compiles the model (~1.5 min)
t0 = time()
truth_run = run_gabls(truth)  # ...so time a second one; this sets the budget below
println("one forward run: ", round(time() - t0; digits = 1), " s")

# Independent Gaussian noise with these standard deviations [K; m/s; degrees]
σ = [fill(0.02, 5); fill(0.05, 5); fill(0.5, 5)]
obs_labels = [q * "@" * string(Int(z)) for q in ("θ", "U", "dir") for z in z_obs]
rng = Random.MersenneTwister(1234)
y_all = truth_run.obs .+ σ .* randn(rng, length(σ))

# ## 4. Sensitivity: which observations can see which parameter?
# Perturb each parameter by ±20% around the prior mean, one at a time, and
# compare the change in each observation with its noise. Observations that no
# parameter moves by more than σ carry no information, so we drop them.
prior_means = [1.4, 0.55, 3.5]
G0 = run_gabls(closure(prior_means)).obs
S = zeros(length(σ), length(prior_means))  # sensitivity table
for j in eachindex(prior_means), s in (0.8, 1.2)
    ϕ = copy(prior_means)
    ϕ[j] *= s
    S[:, j] .= max.(S[:, j], abs.(run_gabls(closure(ϕ)).obs .- G0) ./ σ)
end
println("\n|Δobs| / σ_noise for ±20% parameter changes")
println(rpad("obs", 8), join(lpad.(param_names, 7)))
for i in axes(S, 1)
    println(rpad(obs_labels[i], 8), join(lpad.(round.(S[i, :]; digits = 1), 7)))
end
informative = findall(i -> maximum(S[i, :]) > 1, axes(S, 1))
println("selected for calibration: ", obs_labels[informative])

# ## 5. Calibration with ClimaCalibrate + EKI
struct GABLSInterface <: CAL.AbstractModelInterface
    output_dir::String
    ensemble_size::Int
end
function CAL.forward_model(interface::GABLSInterface, iteration, member)
    (; output_dir) = interface
    member_dir = CAL.path_to_ensemble_member(output_dir, iteration, member)
    toml = TOML.parsefile(CAL.parameter_path(output_dir, iteration, member))
    ϕ = [toml[n]["value"] for n in param_names]
    obs = run_gabls(closure(ϕ); output_dir = member_dir).obs[informative]
    write(joinpath(member_dir, "obs.txt"), join(obs, "\n"))
end
function CAL.observation_map(interface::GABLSInterface, iteration)
    (; output_dir, ensemble_size) = interface
    G = fill(NaN, length(informative), ensemble_size)  # NaN marks a failed member
    for m in 1:ensemble_size
        file = joinpath(CAL.path_to_ensemble_member(output_dir, iteration, m), "obs.txt")
        isfile(file) && (G[:, m] .= parse.(Float64, readlines(file)))
    end
    return G
end

# Priors centred away from the truth (p = 2, c_h = 0.4, β = 5), within bounds
prior = combine_distributions([
    constrained_gaussian("p", prior_means[1], 0.5, 0.5, 4.0),
    constrained_gaussian("c_h", prior_means[2], 0.15, 0.1, 1.5),
    constrained_gaussian("β", prior_means[3], 1.5, 0.5, 15.0),
])
# EKP recommends ≥ 10× as many members as parameters; 10 is enough for this
# smooth, nearly linear problem and keeps the run to about a minute.
ensemble_size, n_iterations = 10, 5
output_dir = mktempdir()
ekp = EKP.EnsembleKalmanProcess(
    EKP.construct_initial_ensemble(rng, prior, ensemble_size),
    y_all[informative], Diagonal(σ[informative] .^ 2), EKP.Inversion(); rng,
)
t0 = time()
ekp = CAL.calibrate(CAL.JuliaBackend(), ekp, GABLSInterface(output_dir, ensemble_size),
    n_iterations, prior, output_dir)
println("calibration: ", round(time() - t0; digits = 1), " s")

ϕ_first, ϕ_final = EKP.get_ϕ_mean(prior, ekp, 1), EKP.get_ϕ_mean_final(prior, ekp)
spread(ϕ) = vec(maximum(ϕ; dims = 2) .- minimum(ϕ; dims = 2))
errors = EKP.get_error(ekp)
for (i, n) in enumerate(param_names)
    println(rpad(n, 4), "truth ", ϕ_true[i], ", initial ensemble mean ",
        round(ϕ_first[i]; sigdigits = 3), ", calibrated ", round(ϕ_final[i]; sigdigits = 3))
end
println("misfit per iteration: ", round.(errors; sigdigits = 3))

# ## 6. Checks
@testset "Custom K-profile closure on GABLS" begin
    # The closure is active: turning vertical diffusion off changes the answer.
    # (With no closure there is nothing to treat implicitly, so run explicitly.)
    no_diffusion = run_gabls(nothing; diff_mode = CA.Explicit())
    @test maximum(abs, no_diffusion.obs .- truth_run.obs) > 10 * maximum(σ)

    # K ≥ 0, finite, and ≈ K_bg above the boundary-layer height
    Y, p = truth_run.simulation.integrator.u, truth_run.simulation.integrator.p
    (; ustar, obukhov_length) = p.precomputed.sfc_conditions
    ᶜz = Fields.coordinate_field(Y.c).z
    ᶜK = similar(Y.c.ρ)
    ᶜK .= CA.ᶜeddy_diffusivity(Y, p, truth)
    h = @. bl_height(truth, ustar, obukhov_length)  # a surface field, one h per column
    ᶜabove_h = @. ᶜz > bl_height(truth, ustar, obukhov_length)  # a 3D Bool field
    K = vec(parent(ᶜK))
    @test all(isfinite, K) && all(≥(0), K)
    @test all(50 .< parent(h) .< 400)  # a shallow stable boundary layer
    @test count(parent(ᶜabove_h)) > 10
    @test all(K[vec(parent(ᶜabove_h))] .≈ truth.K_bg)
    @test maximum(K) > 10 * truth.K_bg

    # The truth run is stably stratified (θ increases with height)
    @test all(diff(truth_run.θ) .> 0)

    # Every calibrated parameter has at least one informative observation
    @test all(j -> maximum(S[informative, j]) > 1, eachindex(param_names))

    # EKI reduces the misfit, moves toward the truth and contracts the ensemble
    @test last(errors) < first(errors)
    for i in eachindex(ϕ_true)
        @test abs(ϕ_final[i] - ϕ_true[i]) < abs(ϕ_first[i] - ϕ_true[i])
        @test abs(ϕ_final[i] - ϕ_true[i]) < 0.25 * ϕ_true[i]
    end
    @test all(spread(EKP.get_ϕ_final(prior, ekp)) .< spread(EKP.get_ϕ(prior, ekp, 1)))
end
