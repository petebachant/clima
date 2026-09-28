"""
    Order1D

Abstract type for interpolation schemes.
"""
abstract type Order1D end

"""
    Extrapolate1D

Abstract type for extrapolation schemes.
"""
abstract type Extrapolate1D end

"""
    Linear <: Order1D

Use linear interpolation.
"""
struct Linear <: Order1D end

"""
    Flat <: Extrapolate1D

Use flat extrapolation.
"""
struct Flat <: Extrapolate1D end

"""
    LinearExtrapolation <: Extrapolate1D

Use linear extrapolation.
"""
struct LinearExtrapolation <: Extrapolate1D end

"""
    get_stencil(alg::Linear, xsource, xtarget; first = 1, extrapolate = Flat(), reverse = false)

This function returns the starting and ending points, in the source grid `xsource`, for the stencil
needed for linear interpolation. If `xtarget` is outside the range of `xsource`, this returns the 
corresponding stencil needed for extrapolation. The stencil specification is characterized by `[st, en]` 
where `st` is the starting point and `en` is the ending point of the stencil in the target grid.
This function returns the tuple `(st, en)`. Linear and Flat extrapolation schemes are supported at the 
boundaries. The argument `first` can be used to speedup the search, by providing a more efficient starting
point for the search.
"""
function get_stencil(
    alg::Linear,
    xsource,
    xtarget;
    first = 1,
    extrapolate = Flat(),
    reverse = false,
)
    last = length(xsource)
    (lowidx, highidx, compare) = reverse ? (last, 1, ≥) : (1, last, ≤)

    if xtarget < xsource[lowidx] # extrapolation
        # Linear extrapolation
        extrapolate == LinearExtrapolation() &&
            (reverse ? (return (last - 1, last)) : (return (1, 2)))
        # Flat extrapolation by default
        return (lowidx, lowidx)
    end
    if xtarget > xsource[highidx] # extrapolation
        # Linear extrapolation
        extrapolate == LinearExtrapolation() &&
            (reverse ? (return (1, 2)) : (return (last - 1, last)))
        # Flat extrapolation by default
        return (highidx, highidx)
    end
    st = first
    for i in first:last
        if compare(xtarget, xsource[i])
            st = max(i - 1, 1)
            break
        end
    end
    return (st, st < last ? st + 1 : st)
end
