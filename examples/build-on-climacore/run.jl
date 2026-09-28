# Build your own model on ClimaCore + ClimaTimeSteppers: 1D heat diffusion.
#
# This script builds a tiny model from scratch:
#   1. pick a device and a communication context with ClimaComms,
#   2. build a vertical column (domain -> mesh -> topology -> space),
#   3. put a temperature Field on it,
#   4. write a diffusion tendency ∂T/∂t = ∇·(K ∇T) with the staggered
#      finite-difference operators and zero-flux boundaries,
#   5. integrate it with an explicit Runge-Kutta method from ClimaTimeSteppers,
#   6. check that total heat is conserved and that the profile smooths.
#
# Run from the repository root:
#   julia --project=examples/build-on-climacore examples/build-on-climacore/run.jl
# Runtime: about 10-30 s on a laptop CPU once packages are precompiled.

import ClimaComms
ClimaComms.@import_required_backends   # loads CUDA etc. only if requested
import ClimaCore: Domains, Meshes, Topologies, Spaces, Fields, Geometry, Operators
import ClimaTimeSteppers as CTS
using Test

const FT = Float64

# ---- 1. Device and context --------------------------------------------------
# `device()` reads CLIMACOMMS_DEVICE (CPU by default); `context(device)` is a
# single-process context unless MPI is loaded. Pick them once, pass them down.
device = ClimaComms.device()
context = ClimaComms.context(device)
ClimaComms.init(context)

# ---- 2. The column ----------------------------------------------------------
# A 1 m column, with cells packed toward the bottom by exponential stretching
# (a non-uniform grid makes the conservation check below more meaningful).
domain = Domains.IntervalDomain(
    Geometry.ZPoint{FT}(0),
    Geometry.ZPoint{FT}(1);
    boundary_names = (:bottom, :top),
)
mesh = Meshes.IntervalMesh(domain, Meshes.ExponentialStretching(FT(0.5)); nelems = 30)
topology = Topologies.IntervalTopology(context, mesh)
center_space = Spaces.CenterFiniteDifferenceSpace(topology)   # cell centers
face_space = Spaces.FaceFiniteDifferenceSpace(center_space)   # cell faces

# ---- 3. Fields --------------------------------------------------------------
# The prognostic temperature lives on cell centers; fluxes live on faces.
# Initial condition: a warm layer between 0.3 and 0.5 m on a 280 K background.
zc = Fields.coordinate_field(center_space).z
T0 = @. FT(280) + FT(10) * exp(-((zc - FT(0.4)) / FT(0.05))^2)

# Put the state in a FieldVector: real models carry several prognostic
# variables (Y.T, Y.q, ...), and ClimaTimeSteppers treats it as one vector.
Y0 = Fields.FieldVector(; T = T0)

# A depth-dependent diffusivity K(z) (m²/s), stored on faces where the flux is
# computed. Precomputed fields like this go into the cache `p`.
zf = Fields.coordinate_field(face_space).z
K = @. FT(1e-3) * (1 + 4 * zf)
p = (; K)

# ---- 4. The tendency --------------------------------------------------------
# GradientC2F maps centers -> faces; DivergenceF2C maps faces -> centers.
# Setting the boundary *flux* to zero on the divergence makes the column
# insulated: no heat enters or leaves. Because the divergence overrides the
# boundary faces, the gradient needs no boundary conditions of its own.
const gradᶠ = Operators.GradientC2F()
const divᶜ = Operators.DivergenceF2C(
    bottom = Operators.SetValue(Geometry.WVector(FT(0))),
    top = Operators.SetValue(Geometry.WVector(FT(0))),
)

# ClimaTimeSteppers calls `T_exp!(dY, Y, p, t)` and expects dY to be filled
# in place. The whole right-hand side is one fused, allocation-free broadcast.
function diffusion_tendency!(dY, Y, p, t)
    @. dY.T = divᶜ(p.K * gradᶠ(Y.T))
    return nothing
end

# ---- 5. Time integration ----------------------------------------------------
# Explicit diffusion is stable for Δt ≲ Δz²/(2K); take a safe fraction of it.
Δz_min = minimum(parent(Fields.Δz_field(center_space)))
Δt = FT(0.2) * Δz_min^2 / maximum(parent(K))
t_end = FT(10)
nsteps = ceil(Int, t_end / Δt)
Δt = t_end / nsteps                              # land exactly on t_end
saveat = collect(range(FT(0), t_end; length = 7))

prob = CTS.ODEProblem(
    CTS.ClimaODEFunction(; T_exp! = diffusion_tendency!),
    Y0,
    (FT(0), t_end),
    p,
)
algo = CTS.ExplicitAlgorithm(CTS.SSP33ShuOsher())  # 3rd-order SSP Runge-Kutta
sol = CTS.solve(prob, algo; dt = Δt, saveat)
@info "Integrated $(nsteps) steps of Δt = $(round(Δt; sigdigits = 3)) s"

# ---- 6. Diagnostics ---------------------------------------------------------
# `sum(field)` is the integral over the space (values × cell thickness), so it
# gives the column heat content ∫T dz in K·m regardless of grid spacing.
heat(Y) = sum(Y.T)
column_depth = sum(ones(center_space))           # ∫1 dz = 1 m
function spread(Y)                               # ∫(T - T̄)² dz
    T̄ = heat(Y) / column_depth
    return sum(@. (Y.T - T̄)^2)
end
Tvals(Y) = Array(parent(Y.T))                    # copy to host for inspection

heats = heat.(sol.u)
spreads = spread.(sol.u)
@info "Heat content (K·m)" initial = heats[1] final = heats[end]
@info "Temperature range (K)" initial = extrema(Tvals(sol.u[1])) final =
    extrema(Tvals(sol.u[end]))

@testset "build-on-climacore: insulated column diffusion" begin
    @test length(sol.u) == length(saveat)
    @test sol.t[end] ≈ t_end
    @test all(Y -> all(isfinite, Tvals(Y)), sol.u)
    @test length(Tvals(sol.u[end])) == Spaces.nlevels(center_space) == 30
    # Zero-flux boundaries: the tendency integrates to zero over the column,
    # so total heat is conserved to round-off.
    dY = similar(Y0)
    diffusion_tendency!(dY, Y0, p, FT(0))
    @test abs(sum(dY.T)) < 1e-12 * maximum(abs, Tvals(dY))
    @test all(h -> isapprox(h, heats[1]; rtol = 1e-12), heats)
    # Diffusion smooths: the variance decreases at every saved time ...
    @test all(diff(spreads) .< 0)
    @test spreads[end] < 0.5 * spreads[1]
    # ... and the maximum principle holds: the peak falls, the minimum rises,
    # and everything stays within the initial range.
    T_first, T_last = Tvals(sol.u[1]), Tvals(sol.u[end])
    @test maximum(T_last) < maximum(T_first)
    @test minimum(T_last) > minimum(T_first)
    @test all(Y -> 280 - 1e-10 ≤ minimum(Tvals(Y)) ≤ maximum(Tvals(Y)) ≤ 290, sol.u)
    # Physically sensible: still near the 280 K background plus the spread-out bump.
    @test 280 < heats[end] < 290
end
