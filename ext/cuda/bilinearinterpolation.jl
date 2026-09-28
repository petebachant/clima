import ..ClimaInterpolations.BilinearInterpolation:
    Bilinear, set_source_range!, interpolatebilinear!, get_dims
import ..get_maxgridsize


"""
    interpolatebilinear!(
        ftarget::CuArray{FT,N},
        bilinear::B,
        fsource::CuArray{FT,N},
    ) where {FT,N,B}

This is the `CUDA` implementation of the `interpolatebilinear!` function.

Interpolate `fsource`, defined on source grid, onto the target grid.
The horizontal source and target grids are defined in `bilinear`.
Here `fsource` is an N-dimensional array where the last two dimensions are assumed to be horizontal dimensions.

For example, `fsource` can be of size `[n1, n2..., nx, ny]`, where `nx` and `ny` are the horizontal dimensions.
Single horizontal level is also supported.
The number of horizontal levels should be same for both source and target arrays.

The interpolation is parallelized by distributing the horizontal target points across a `(nxblocks, nyblocks)` sized CUDA grid.
All vertical levels are placed on the same CUDA block.
When `nlevels` exceeds `nthreads`, `nzloops` loops are executed by each thread to process all vertical levels.
Similarly, when `ntargetx` exceeds `nxblocks` or `ntargety` exceeds `nyblocks`, `nxloops`/`nyloops` are executed
by all threads in a given block per that direction.
"""
function interpolatebilinear!(
    ftarget::CuArray{FT, N},
    bilinear::B,
    fsource::CuArray{FT, N},
) where {FT, N, B}
    @assert N ≥ 2
    (leveldimssource..., nxs, nys) = size(fsource)
    (leveldimstarget..., nxt, nyt) = size(ftarget)

    nsourcex, nsourcey, ntargetx, ntargety = get_dims(bilinear)

    # ensure number of vertical levels are same between fsource and ftarget
    @assert leveldimssource == leveldimstarget
    # ensure horizontal dimensions of fsource match with horizontal source grid dimensions 
    # in bilinear 
    @assert nxs == nsourcex && nys == nsourcey
    # ensure horizontal dimensions of ftarget match with horizontal target grid dimensions
    # in bilinear
    @assert nxt == ntargetx && nyt == ntargety
    # target n loops per dimension per block/threadgroup
    # It was found to be more efficent to process multiple loops per block/threadgroup
    targetloopsperblockdimx = 4
    targetloopsperblockdimy = 4
    maxblocksperxdim, maxblocksperydim, _ = get_maxgridsize()
    nxblocks = min(cld(ntargetx, targetloopsperblockdimx), maxblocksperxdim)
    nyblocks = min(cld(ntargety, targetloopsperblockdimy), maxblocksperydim)

    nxloops = cld(ntargetx, nxblocks)
    nyloops = cld(ntargety, nyblocks)

    levelcidxs = CartesianIndices(leveldimssource)
    nlevels = length(levelcidxs)

    kernel = @cuda launch = false interpolatebilinear_kernel!(
        ftarget,
        bilinear,
        fsource,
        levelcidxs,
        (nxloops, ntargetx),
        (nyloops, ntargety),
        (1, 1),
    )
    kernel_config = CUDA.launch_configuration(kernel.fun)
    nthreads = min(kernel_config.threads, nlevels)
    nzloops = cld(nlevels, nthreads)

    @cuda threads = nthreads blocks = (nxblocks, nyblocks) interpolatebilinear_kernel!(
        ftarget,
        bilinear,
        fsource,
        levelcidxs,
        (nxloops, ntargetx),
        (nyloops, ntargety),
        (nzloops, nlevels),
    )
    return nothing
end

"""
    interpolatebilinear_kernel!(
        ftarget::AbstractArray{FT, N},
        bilinear::B,
        fsource::AbstractArray{FT, N},
        levelcidxs,
        (nxloops, ntargetx),
        (nyloops, ntargety),
        (nzloops, nlevels),
    ) where {FT, N, B}

This is the CUDA kernel, executed on the CUDA device, for the `interpolatebilinear!` function.
"""
function interpolatebilinear_kernel!(
    ftarget::AbstractArray{FT, N},
    bilinear::B,
    fsource::AbstractArray{FT, N},
    levelcidxs,
    (nxloops, ntargetx),
    (nyloops, ntargety),
    (nzloops, nlevels),
) where {FT, N, B}
    (; sourcex, sourcey, targetx, targety, startx, starty) = bilinear

    ixtg, iytg = blockIdx().x, blockIdx().y
    izt = threadIdx().x
    nzthreads = blockDim().x
    (nxblocks, nyblocks) = gridDim().x, gridDim().y

    @inbounds begin
        for yl in 1:nyloops
            iy = iytg + (yl - 1) * nyblocks
            iy ≤ ntargety || continue
            y, sty = targety[iy], starty[iy]
            y1, y2 = sourcey[sty], sourcey[sty + 1]
            dy1 = y - y1
            dy2 = y2 - y
            for xl in 1:nxloops
                ix = ixtg + (xl - 1) * nxblocks
                ix ≤ ntargetx || continue
                x, stx = targetx[ix], startx[ix]
                x1, x2 = sourcex[stx], sourcex[stx + 1]

                dx1 = x - x1
                dx2 = x2 - x

                fac = FT(1) / ((x2 - x1) * (y2 - y1))

                for zl in 1:nzloops
                    iz = izt + (zl - 1) * nzthreads
                    iz ≤ nlevels || continue
                    levelidx = Tuple(levelcidxs[iz])

                    ftarget[levelidx..., ix, iy] =
                        (
                            dx1 * (
                                dy2 * fsource[levelidx..., stx + 1, sty] +
                                dy1 * fsource[levelidx..., stx + 1, sty + 1]
                            ) +
                            dx2 * (
                                dy1 * fsource[levelidx..., stx, sty + 1] +
                                dy2 * fsource[levelidx..., stx, sty]
                            )
                        ) * fac
                end
            end
        end

    end
    return nothing
end

function Bilinear(
    sourcex::V,
    sourcey::V,
    targetx::V,
    targety::V,
) where {V <: CuVector}
    startx = similar(targetx, Int)
    starty = similar(targety, Int)
    # Call set_source_range_kernel! with one thread per group
    # and two threadgroups
    @cuda threads = 1 blocks = 2 set_source_range_kernel!(
        startx,
        sourcex,
        targetx,
        starty,
        sourcey,
        targety,
    )
    return Bilinear(sourcex, sourcey, targetx, targety, startx, starty)
end

"""
    set_source_range_kernel!(
        startx::AbstractVector{I},
        sourcex::AbstractVector{FT},
        targetx::AbstractVector{FT},
        starty::AbstractVector{I},
        sourcey::AbstractVector{FT},
        targety::AbstractVector{FT},
    ) where {I, FT}

This is the CUDA kernel for the `set_source_range!` function.
"""
function set_source_range_kernel!(
    startx::AbstractVector{I},
    sourcex::AbstractVector{FT},
    targetx::AbstractVector{FT},
    starty::AbstractVector{I},
    sourcey::AbstractVector{FT},
    targety::AbstractVector{FT},
) where {I, FT}
    order = Linear()
    bid = blockIdx().x
    tid = threadIdx().x
    (bid == 1 && tid == 1) && set_source_range!(startx, sourcex, targetx)
    (bid == 2 && tid == 1) && set_source_range!(starty, sourcey, targety)
    return nothing
end
