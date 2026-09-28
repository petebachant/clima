# Calibrate the parameters of a cheap toy model with ClimaCalibrate and
# EnsembleKalmanProcesses (EKP).
#
# The "model" is logistic population growth, N(t) = K / (1 + (K/N0 - 1) e^{-rt}),
# with an unknown growth rate `r` and carrying capacity `K`. We generate a
# synthetic observation from known "true" values, start from a prior that is
# deliberately off, and let ensemble Kalman inversion pull the parameters back
# toward the truth. Swap `logistic` for a call into your own model and the rest
# of the script stays the same.
#
# Run it from the repository root with
#
#     julia --project=examples/calibrate-toy-model examples/calibrate-toy-model/run.jl
#
# It takes about 30 s on a laptop, almost all of it compilation; the calibration
# itself (8 members x 5 iterations) runs in about a second.

import ClimaCalibrate as CAL
import EnsembleKalmanProcesses as EKP
import EnsembleKalmanProcesses.ParameterDistributions:
    combine_distributions, constrained_gaussian
import Random
import TOML
using Test

# ## The forward model
# Any function from parameters to a vector of outputs will do.
logistic(r, K, t; N0 = 10.0) = @. K / (1 + (K / N0 - 1) * exp(-r * t))

# ## The model interface
# ClimaCalibrate talks to a model through a subtype of `AbstractModelInterface`.
# `forward_model` and `observation_map` only get the iteration and member
# numbers, so everything else they need (output directory, ensemble size,
# observation times) lives in the struct's fields.
struct LogisticInterface <: CAL.AbstractModelInterface
    output_dir::String
    ensemble_size::Int
    t::Vector{Float64}
end

# Run one ensemble member. ClimaCalibrate has already written the parameters EKP
# drew for this member to `parameter_path`, as a TOML file with one table per
# parameter; we read them, run the model, and save its output in the member's
# own directory.
function CAL.forward_model(interface::LogisticInterface, iteration, member)
    (; output_dir, t) = interface
    params = TOML.parsefile(CAL.parameter_path(output_dir, iteration, member))
    r = params["growth_rate"]["value"]
    K = params["carrying_capacity"]["value"]
    N = logistic(r, K, t)
    member_dir = CAL.path_to_ensemble_member(output_dir, iteration, member)
    write(joinpath(member_dir, "population.txt"), join(N, "\n"))
    return nothing
end

# Gather every member's output into the "G ensemble" matrix: one column per
# member, rows in the same order as the observation vector.
function CAL.observation_map(interface::LogisticInterface, iteration)
    (; output_dir, ensemble_size, t) = interface
    G = fill(NaN, length(t), ensemble_size)  # NaN columns mark failed members
    for m in 1:ensemble_size
        file = joinpath(
            CAL.path_to_ensemble_member(output_dir, iteration, m),
            "population.txt",
        )
        isfile(file) && (G[:, m] .= parse.(Float64, readlines(file)))
    end
    return G
end

# ## The observation (a perfect-model experiment)
t = collect(0.0:2.0:20.0)
truth = (; growth_rate = 0.5, carrying_capacity = 200.0)
observation = logistic(truth.growth_rate, truth.carrying_capacity, t)

# The noise covariance tells EKP how much misfit to blame on observational
# error. Here: independent errors with a standard deviation of 2 individuals.
noise = 4.0 * EKP.I(length(t))

# ## The prior
# `constrained_gaussian(name, mean, std, lower, upper)` builds a distribution
# with the requested moments that respects the bounds; both parameters here
# must be positive. The prior means are deliberately far from the truth.
prior = combine_distributions([
    constrained_gaussian("growth_rate", 0.3, 0.2, 0, Inf),
    constrained_gaussian("carrying_capacity", 120.0, 50.0, 0, Inf),
])

# ## Calibrate
# A tiny ensemble and a handful of iterations suffice for two parameters and a
# model this smooth. Passing one seeded RNG to EKP makes the run reproducible.
ensemble_size = 8
n_iterations = 5
rng = Random.MersenneTwister(42)
output_dir = mktempdir()  # all calibration files go here and are cleaned up

ekp = EKP.EnsembleKalmanProcess(
    EKP.construct_initial_ensemble(rng, prior, ensemble_size),
    observation,
    noise,
    EKP.Inversion();
    rng,
)

interface = LogisticInterface(output_dir, ensemble_size, t)
ekp = CAL.calibrate(
    CAL.JuliaBackend(),  # runs members one after another in this process
    ekp,
    interface,
    n_iterations,
    prior,
    output_dir,
)

# ## Results
# `get_ϕ_mean` returns the ensemble mean in constrained (physical) space.
n_done = EKP.get_N_iterations(ekp)  # EKP may stop early once converged
ϕ_first = EKP.get_ϕ_mean(prior, ekp, 1)
ϕ_final = EKP.get_ϕ_mean_final(prior, ekp)
θ_true = [truth.growth_rate, truth.carrying_capacity]
errors = EKP.get_error(ekp)  # covariance-weighted data misfit per iteration
spread(ϕ) = vec(maximum(ϕ; dims = 2) .- minimum(ϕ; dims = 2))
println("Iterations run:         ", n_done)
println("Initial mean (r, K):    ", round.(ϕ_first; sigdigits = 3))
println("Calibrated mean (r, K): ", round.(ϕ_final; sigdigits = 3))
println("Truth (r, K):           ", θ_true)
println("Misfit per iteration:   ", round.(errors; sigdigits = 3))

@testset "Toy-model calibration" begin
    @test n_done >= 1
    @test all(isfinite, ϕ_final)
    @test all(>(0), EKP.get_ϕ_final(prior, ekp))  # bounds are respected
    # Each parameter moves toward the value the observation was made with
    for i in eachindex(θ_true)
        @test abs(ϕ_final[i] - θ_true[i]) < abs(ϕ_first[i] - θ_true[i])
    end
    # ...and lands close to it (within 10%)
    @test all(abs.(ϕ_final .- θ_true) .< 0.1 .* θ_true)
    # The data misfit drops and the ensemble contracts as it learns
    @test last(errors) < first(errors)
    @test all(
        spread(EKP.get_ϕ_final(prior, ekp)) .<
        spread(EKP.get_ϕ(prior, ekp, 1)),
    )
    # The G ensemble has one row per observation and one column per member
    @test size(EKP.get_g_final(ekp)) == (length(t), ensemble_size)
    # ClimaCalibrate wrote one parameter file per member per iteration
    @test isfile(CAL.parameter_path(output_dir, 1, ensemble_size))
    @test CAL.last_completed_iteration(output_dir) == n_done
end

rm(output_dir; recursive = true)
