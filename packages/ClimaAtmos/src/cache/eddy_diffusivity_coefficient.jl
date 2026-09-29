"""
    ᶜcompute_eddy_diffusivity_coefficient(ᶜρ, vert_diff::DecayWithHeightDiffusion)
    ᶜcompute_eddy_diffusivity_coefficient(ᶜuₕ, ᶜp, vert_diff::VerticalDiffusion)

Return a lazy broadcast of the eddy diffusivity at cell centers [m²/s] for the
given vertical diffusion model.

For `DecayWithHeightDiffusion`, the diffusivity decays exponentially with height
above the surface with scale height `H` from its surface value `D₀`. For
`VerticalDiffusion`, it is built from the bulk transfer coefficient `C_E`, the
wind speed at the lowest level, and half the depth of the lowest cell, and is
tapered above the planetary boundary layer as a function of pressure; see
`eddy_diffusivity_coefficient_H` and `eddy_diffusivity_coefficient` in
`precomputed_quantities.jl`.
"""
function ᶜcompute_eddy_diffusivity_coefficient(
    ᶜρ,
    vert_diff::DecayWithHeightDiffusion,
)
    (; ᶜz, ᶠz) = z_coordinate_fields(axes(ᶜρ))
    ᶠz_sfc = Fields.level(ᶠz, Fields.half)
    return @. lazy(
        eddy_diffusivity_coefficient_H(vert_diff.D₀, vert_diff.H, ᶠz_sfc, ᶜz),
    )
end

function ᶜcompute_eddy_diffusivity_coefficient(
    ᶜuₕ,
    ᶜp,
    vert_diff::VerticalDiffusion,
)
    interior_uₕ = Fields.level(ᶜuₕ, 1)
    ᶜΔz_surface = Fields.Δz_field(interior_uₕ)
    return @. lazy(
        eddy_diffusivity_coefficient(
            vert_diff.C_E,
            norm(interior_uₕ),
            ᶜΔz_surface / 2,
            ᶜp,
        ),
    )
end

"""
    ᶜeddy_diffusivity(Y, p, vertical_diffusion::AbstractVerticalDiffusion)

Return a lazy broadcast of the cell-center eddy diffusivity [m²/s] of the
vertical diffusion closure `vertical_diffusion`, given the state `Y` and cache
`p`.

This is the extension point for boundary-layer closures. The vertical diffusion
tendency, its implicit Jacobian, and the `edt`/`evu` diagnostics all get the
diffusivity from this function, so a new closure needs only a subtype of
[`AbstractVerticalDiffusion`](@ref) and one method:

```julia
import ClimaAtmos as CA
import ClimaCore: Fields

struct MyClosure{FT} <: CA.AbstractVerticalDiffusion
    K₀::FT  # surface diffusivity [m²/s]
    H::FT   # decay height [m]
end
function CA.ᶜeddy_diffusivity(Y, p, c::MyClosure)
    ᶜz = Fields.coordinate_field(Y.c).z
    return @. c.K₀ * exp(-ᶜz / c.H)  # a Field or a lazy broadcast
end
```

Pass it with `AtmosModel(grid; vertical_diffusion = MyClosure(1.0, 500.0), ...)`.
The result is copied into scratch space, so returning either a `Field` or a
lazy broadcast works. The precomputed quantities in `p.precomputed` (e.g.
`ᶜp`, `ᶜT`, `ᶜu`) and the surface conditions in `p.precomputed.sfc_conditions`
are up to date when this is called. By default, closures also diffuse
momentum; define `CA.disable_momentum_vertical_diffusion(::MyClosure) = true`
to diffuse scalars only.
"""
ᶜeddy_diffusivity(Y, p, vert_diff::DecayWithHeightDiffusion) =
    ᶜcompute_eddy_diffusivity_coefficient(Y.c.ρ, vert_diff)
ᶜeddy_diffusivity(Y, p, vert_diff::VerticalDiffusion) =
    ᶜcompute_eddy_diffusivity_coefficient(Y.c.uₕ, p.precomputed.ᶜp, vert_diff)
