module Interpolation1D

using DocStringExtensions
import Adapt

include("stencils1d.jl")

"""
    interpolate(xpts, fval, xtarg)

Interpolate `fval` defined on `xpts` at `xtarg`.
Reference:
1). Berrut, J., and Trefethen, L. N., 2004. Barycentric Lagrange Interpolation, SIAM REVIEW
Vol. 46, No. 3, pp. 501–517.
DOI. 10.1137/S0036144502417715
"""
@inline function interpolate(
    xpts::AbstractArray{FT, 1},
    fval::AbstractArray{FT, 1},
    xtarg::FT,
) where {FT <: AbstractFloat}
    length(xpts) == 1 && return fval[1] # flat extrapolation
    l, result, midx, tolerance = FT(1), -FT(0), 0, (10 * eps(FT))
    @inbounds begin
        for i in eachindex(xpts)
            dx = xtarg - xpts[i]
            if abs(dx) < tolerance # target point is coincident with a source point
                midx = i # matching idx in source grid xpts
                break
            else
                l *= dx # accumulate product
            end
        end
        if midx == 0
            for i in eachindex(xpts)
                xi = xpts[i]
                wi = FT(1)
                for j in eachindex(xpts)
                    if j ≠ i
                        wi *= (xi - xpts[j])
                    end
                end
                result += fval[i] * l / ((xtarg - xi) * wi)
            end
        else
            result = fval[midx]
        end
    end
    return result
end

"""
    interpolate1d!(
        ftarget::AbstractArray{FT, N},
        xsource::AbstractArray{FT, NSG},
        xtarget::AbstractArray{FT, NTG},
        fsource::AbstractArray{FT, N},
        order,
        extrapolate = Flat(),
        reverse = false,
    ) where {FT, N, NSG, NTG}

Interpolate `fsource`, defined on grid `xsource`, onto the `xtarget` grid.
Here the source grid `xsource` is an N-dimensional array of columns.
The first dimension is assumed to be the column dimension. 
Each column can have a different grid. It is assumed that both `xsource` and
`xtarget` are either mononically increasing (`reverse = false`) or decreasing
(`reverse = true`).
"""
function interpolate1d!(
    ftarget::AbstractArray{FT, N},
    xsource::AbstractArray{FT, NSG},
    xtarget::AbstractArray{FT, NTG},
    fsource::AbstractArray{FT, N},
    order,
    extrapolate = Flat();
    reverse = false,
) where {FT, N, NSG, NTG}
    @assert N ≥ 1
    @assert NSG == 1 || NSG == N # Source grid can be the same for all columns or different for each column
    @assert NTG == 1 || NTG == N # Target grid can be the same for all columns or different for each column
    (nsource, coldims_source...) = size(fsource)
    (ntarget, coldims_target...) = size(ftarget)
    @assert coldims_source == coldims_target # check if column count and shape is same between source and target
    @assert ntarget == size(xtarget, 1) # check if column length is same between ftarget and xtarget
    @assert nsource == size(xsource, 1) # check if column length is same between fsource and xsource
    coldims = coldims_source
    colcidxs = CartesianIndices(coldims)
    @inbounds begin
        for colcidx in colcidxs
            colidx = Tuple(colcidx)
            colidxsource = _get_grid_colidx(NSG, colidx)
            colidxtarget = _get_grid_colidx(NTG, colidx)
            interpolate_column!(
                view(ftarget, :, colidx...),
                view(xsource, :, colidxsource...),
                view(xtarget, :, colidxtarget...),
                view(fsource, :, colidx...),
                order,
                extrapolate,
                reverse = reverse,
            )
        end
    end
    return nothing
end

"""
    interpolate_column!(
        ftarget,
        xsource,
        xtarget,
        fsource,
        order,
        extrapolate;
        reverse = false,
    )

Interpolate `fsource`, defined on column (`1D`) grid `xsource`, onto the `xtarget` grid.
It is assumed that both `xsource` and `xtarget` are either mononically increasing 
(`reverse = false`) or decreasing (`reverse = true`). This is a convenience function 
primarily intended for internal use.
"""
@inline function interpolate_column!(
    ftarget,
    xsource,
    xtarget,
    fsource,
    order,
    extrapolate;
    reverse = false,
)
    first = 1
    @inbounds begin
        for (i, x) in enumerate(xtarget)
            (st, en) = get_stencil(
                order,
                xsource,
                x,
                first = first,
                extrapolate = extrapolate,
                reverse = reverse,
            )
            first = st
            ftarget[i] =
                interpolate(view(xsource, st:en), view(fsource, st:en), x)
        end
    end
    return nothing
end

@inline _get_grid_colidx(NG, colidx) = NG == 1 ? () : colidx

"""
    Interpolate1D{V, IO, EO}

This struct stores the source grid (`xsource`), function defined on the source grid (`fsource`),
interpolation order and extrapolation order for 1-dimensional interpolation.
This struct is designed to be be used in broadcasting calls for 1-dimensional interpolation.

E.g.: 

itp = Interpolate1D(
            xsource,
            fsource,
            interpolationorder = Linear(),
            extrapolationorder = extrapolation,
        )

ftarget = itp.(xtarget)
"""
struct Interpolate1D{V, IO, EO}
    xsource::V
    fsource::V
    interpolationorder::IO
    extrapolationorder::EO
    reverse::Bool
end

Adapt.@adapt_structure Interpolate1D
Base.broadcastable(itp::Interpolate1D) = Ref(itp)

function Interpolate1D(
    xsource,
    fsource;
    interpolationorder = Linear(),
    extrapolationorder = Flat(),
    reverse = false,
)
    @assert length(xsource) == length(fsource)
    return Interpolate1D(
        xsource,
        fsource,
        interpolationorder,
        extrapolationorder,
        reverse,
    )
end

function (itp::Interpolate1D)(xtargetpoint)
    (; xsource, fsource, interpolationorder, extrapolationorder, reverse) = itp
    st, en = get_stencil(
        interpolationorder,
        xsource,
        xtargetpoint,
        extrapolate = extrapolationorder,
        reverse = reverse,
    )
    return @inbounds interpolate(
        view(xsource, st:en),
        view(fsource, st:en),
        xtargetpoint,
    )
end

end
