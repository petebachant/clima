import ClimaInterpolations.Interpolation1D:
    _get_grid_colidx, interpolate_column!

function interpolate1d!(
    ftarget::CuArray{FT, N},
    xsource::CuArray{FT, NSG},
    xtarget::CuArray{FT, NTG},
    fsource::CuArray{FT, N},
    order,
    extrapolate = ClimaInterpolations.Interpolation1D.Flat();
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
    nitems = length(colcidxs)
    kernel = @cuda launch = false interpolate1d_kernel!(
        ftarget,
        xsource,
        xtarget,
        fsource,
        order,
        extrapolate,
        colcidxs,
        reverse,
    )
    kernel_config = CUDA.launch_configuration(kernel.fun)
    nthreads = min(kernel_config.threads, nitems)
    nblocks = convert(Int, cld(nitems, nthreads))

    @cuda threads = nthreads blocks = nblocks interpolate1d_kernel!(
        ftarget,
        xsource,
        xtarget,
        fsource,
        order,
        extrapolate,
        colcidxs,
        reverse,
    )
    return nothing
end

function interpolate1d_kernel!(
    ftarget::AbstractArray{FT, N},
    xsource::AbstractArray{FT, NSG},
    xtarget::AbstractArray{FT, NTG},
    fsource::AbstractArray{FT, N},
    order,
    extrapolate,
    colcidxs,
    reverse,
) where {FT, N, NSG, NTG}
    nitems = length(colcidxs)
    # obtain the column number processed by each thread
    gid = threadIdx().x + (blockIdx().x - 1) * blockDim().x

    if gid ≤ nitems
        colidx = Tuple(colcidxs[gid])
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
    return nothing
end
