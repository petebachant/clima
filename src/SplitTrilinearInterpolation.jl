module SplitTrilinearInterpolation
using DocStringExtensions

import ..Interpolation1D: Linear, Flat, interpolate1d!
import ..BilinearInterpolation: Bilinear, interpolatebilinear!, get_dims

"""
    SplitTrilinear{VS, VT, HB, W1, W2}

This struct stores the source and target grids and work arrays for split trilinear interpolation.

# Fields
$(DocStringExtensions.FIELDS)
"""
struct SplitTrilinear{VS, VT, HB, W1, W2}
    "Vertical source grid"
    vsource::VS
    "Vertical target grid"
    vtarget::VT
    "`Bilinear` object containing the horizontal source and target grids"
    bilinear::HB
    "work array, storing fsource on the target horizontal grid"
    fsource_intermediate::W1
    "vertical source grid corresponding to target horizontal grid"
    vsource_intermediate::W2
end

"""
    SplitTrilinear(
        (vsource, h1source, h2source),
        (vtarget, h1target, h2target);
    )

A constructor for the `SplitTrilinear` object. Here,
- `vsource` is the vertical source grid. It can be same for all columns (a 1D array) or different for each of the columns (a 3D array, with the first dimension being the column dimension)
- `h1source` is the source grid along the first horizontal direction
- `h2source` is the source grid along the second horizontal direction
- `vtarget` is the vertical target grid. It can be same for all columns (a 1D array) or different for each of the columns (a 3D array, with the first dimension being the column dimension)
- `h1target` is the target grid along the first horizontal direction (1D array)
- `h2target` is the target grid along the second horizontal direction (1D array)
"""
function SplitTrilinear(
    (vsource, h1source, h2source),
    (vtarget, h1target, h2target);
)
    bilinear = Bilinear(h1source, h2source, h1target, h2target)
    nvsource = size(vsource, 1)
    _, _, nh1target, nh2target = get_dims(bilinear)
    fsource_intermediate = similar(vsource, nvsource, nh1target, nh2target)
    # If the column grid is identical for all columns (i.e. `vsource` is a 1D array),
    # this step can be skipped and `vsource_intermediate` is identical to `vsource`. 
    # However, if that is not the case, use bilinear interpolation to compute the 
    # `vsource_intermediate` on the target horizontal grid, at each level, using bilinear interpolation.
    vsource_intermediate =
        ndims(vsource) == 1 ? vsource :
        similar(vsource, nvsource, nh1target, nh2target)
    ndims(vsource) == 1 ||
        interpolatebilinear!(vsource_intermediate, bilinear, vsource)
    return SplitTrilinear(
        vsource,
        vtarget,
        bilinear,
        fsource_intermediate,
        vsource_intermediate,
    )
end

"""
    split_trilinear_interpolation!(
        ftarget,
        split_trilinear::SplitTrilinear,
        fsource;
        vextrapolate = Flat(),
        vreverse = false,
    )

Interpolate the data `fsource` defined on a source grid onto the target grid using split trilinear interpolation.
This specific function uses the "horizontal first" approach. The following sequence of steps are used for this 
interpolation:

1). Interpolate `fsource` onto the target horizontal grid, using blinear interpolation, at each of the vertical
levels. Store the result in `fsource_intermediate` work array.

2). If the column grid is identical for all columns, this step can be skipped and `vsource_intermediate` is identical
to `vsource`. However, if that is not the case, use bilinear interpolation to compute the `vsource_intermediate` on
the target horizontal grid, at each level, using bilinear interpolation. This step is handled by the constructor above.

3). Use 1D linear interpolation, for each column, to interpolate `fsource_intermediate` onto the target grid.
"""
function split_trilinear_interpolation!(
    ftarget,
    split_trilinear::SplitTrilinear,
    fsource;
    vextrapolate = Flat(),
    vreverse = false,
)
    (; vtarget, bilinear, fsource_intermediate, vsource_intermediate) =
        split_trilinear
    # applies bilinear interpolation at each horizontal level
    interpolatebilinear!(fsource_intermediate, bilinear, fsource)
    # then apply linear interpolation in the vertical direction
    interpolate1d!(
        ftarget,
        vsource_intermediate,
        vtarget,
        fsource_intermediate,
        Linear(),
        vextrapolate,
        reverse = vreverse,
    )
    return nothing
end

split_trilinear_interpolation!(
    ftarget,
    (vsource, h1source, h2source),
    (vtarget, h1target, h2target),
    fsource;
    vextrapolate = Flat(),
    vreverse = false,
) = split_trilinear_interpolation!(
    ftarget,
    SplitTrilinear(
        (vsource, h1source, h2source),
        (vtarget, h1target, h2target),
    ),
    fsource,
    vextrapolate = vextrapolate,
    vreverse = vreverse,
)

end
