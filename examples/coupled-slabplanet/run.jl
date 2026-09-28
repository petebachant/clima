# # The smallest coupled simulation: a "slabplanet"
#
# This example runs ClimaCoupler with three interacting components on the sphere:
#   - a ClimaAtmos atmosphere (gray radiation, 0-moment microphysics),
#   - a ClimaLand "bucket" land model (on continents, from a land-sea mask),
#   - a thermal slab ocean (everywhere else), with no sea ice.
# The coupler computes turbulent surface fluxes between the atmosphere and each
# surface every coupling step, and tracks global energy and water budgets.
#
# Run it from the repository root with:
#     julia --project=examples/coupled-slabplanet examples/coupled-slabplanet/run.jl
#
# Runtime: about 3.5 minutes on one laptop CPU thread (after package
# precompilation), almost all of it compiling the model; the 5 coupling steps
# themselves take well under a second. Peak memory is about 5 GB resident.
# Downloads one small (<1 MB) land-sea mask artifact on first use.

import ClimaComms
ClimaComms.@import_required_backends
using ClimaCoupler
# Loading ClimaAtmos and ClimaLand activates ClimaCoupler's extensions for them,
# which provide the atmosphere and land component models.
import ClimaAtmos
import ClimaLand
import ClimaCore
using Test

# WORKAROUND (remove once fixed in ClimaCore): the coupler copies atmosphere
# surface fields (a level of the 3D atmosphere space) onto its 2D boundary space.
# At HEAD, ClimaCore's `Spaces.issubspace` has no method saying that a level
# space and the horizontal space of the same grid are compatible, so every global
# coupled run errors with "Cannot remap between distinct spectral-element spaces".
# This method restores that compatibility check.
ClimaCore.Spaces.issubspace(
    a::ClimaCore.Spaces.AbstractSpectralElementSpace,
    b::ClimaCore.Spaces.AbstractSpectralElementSpace,
) =
    a === b ||
    ClimaCore.Spaces.horizontal_grid(ClimaCore.Spaces.grid(a)) ===
    ClimaCore.Spaces.horizontal_grid(ClimaCore.Spaces.grid(b))

# ## 1. Start from a ready-made configuration
# ClimaCoupler runs are driven by a configuration dictionary. We begin from the
# `slabplanet_default.yml` file shipped with ClimaCoupler; `get_coupler_config_dict`
# fills in every option not in the file with ClimaCoupler and ClimaAtmos defaults.
config_file = joinpath(pkgdir(ClimaCoupler), "config", "ci_configs", "slabplanet_default.yml")
config = Input.get_coupler_config_dict(config_file)

# ## 2. Make it as small and short as possible
output_dir = mktempdir()
config["job_id"] = "coupled_slabplanet"
config["coupler_output_dir"] = output_dir  # all output goes to a temp directory
config["mode_name"] = "slabplanet"          # atmosphere + bucket land + slab ocean
config["device"] = "CPUSingleThreaded"
config["h_elem"] = 2                        # 2x2 spectral elements per cubed-sphere face
config["z_elem"] = 10                       # 10 vertical levels
config["z_max"] = 30000.0                   # model top at 30 km
config["dt"] = "200secs"                    # component model time step
config["dt_cpl"] = "200secs"                # coupling time step
config["t_end"] = "1000secs"                # 5 coupling steps
config["bucket_albedo_type"] = "function"   # analytic land albedo: no data download
config["energy_check"] = true               # log global energy and water budgets
config["use_coupler_diagnostics"] = false   # skip NetCDF output to keep things quick
# WORKAROUND: at HEAD, `use_land_diagnostics = false` errors for the bucket model
# (`output_writer` is never assigned), so we keep them on. With the default monthly
# period, nothing is written during this short run.
config["use_land_diagnostics"] = true
config["output_default_diagnostics"] = false
config["checkpoint_dt"] = "1000days"        # never checkpoint in this short run
config["walltime_debug"] = false
config["print_config_dict"] = false          # quieter logs when the simulation is built

# ## 3. Build and run the coupled simulation
cs = CoupledSimulation(config)
(; atmos_sim, land_sim, ocean_sim) = cs.model_sims
@info "Component models" nameof(typeof(atmos_sim)) nameof(typeof(land_sim)) nameof(typeof(ocean_sim))

# Surface temperature of each surface before we step, on the coupler's
# boundary (surface) space.
boundary_space = Interfacer.boundary_space(cs)
T_ocean_initial = copy(Interfacer.get_field(boundary_space, ocean_sim, Val(:surface_temperature)))

run!(cs)

# ## 4. Inspect the result
# The coupler keeps the merged surface state and fluxes in `cs.fields`.
# The area fractions of land and ocean should tile the surface exactly.
land_fraction = cs.fields.land_area_fraction
ocean_fraction = cs.fields.ocean_area_fraction
T_sfc = cs.fields.T_sfc      # area-weighted combined surface temperature [K]
F_sh = cs.fields.F_sh        # sensible heat flux [W m⁻²]
F_lh = cs.fields.F_lh        # latent heat flux [W m⁻²]
T_ocean = Interfacer.get_field(boundary_space, ocean_sim, Val(:surface_temperature))

# Global energy budget: atmosphere + land + ocean + accumulated net radiation
# through the top of the atmosphere. In a closed slabplanet it should be constant.
energy = cs.conservation_checks.energy.sums.total
water = cs.conservation_checks.water.sums.total
rel_energy_drift = abs(energy[end] - energy[1]) / abs(energy[1])
rel_water_drift = abs(water[end] - water[1]) / abs(water[1])
@info "Global budget drift over the run" rel_energy_drift rel_water_drift

@testset "Coupled slabplanet" begin
    # The run reached its end time after the expected number of coupling steps.
    @test float(cs.t[]) ≈ 1000
    @test cs.step[] == 5

    # Land and ocean are both present and together cover the whole sphere.
    @test 0 < Utilities.integral(land_fraction) < Utilities.integral(ocean_fraction)
    @test all(x -> x ≈ 1, parent(land_fraction .+ ocean_fraction))

    # Surface temperatures and fluxes are finite and physically plausible.
    @test all(isfinite, parent(T_sfc))
    @test all(x -> 200 < x < 330, parent(T_sfc))
    @test all(isfinite, parent(F_sh)) && all(isfinite, parent(F_lh))
    @test maximum(abs, parent(F_sh)) < 1000
    @test maximum(abs, parent(F_lh)) < 2000

    # The slab ocean is prognostic: its temperature evolved, but only slightly.
    @test T_ocean != T_ocean_initial
    @test maximum(abs, parent(T_ocean .- T_ocean_initial)) < 1

    # Global energy and water are conserved to within a small relative error.
    @test length(energy) >= cs.step[]
    @test rel_energy_drift < 1e-4
    @test rel_water_drift < 1e-3
end
