import ClimaInterpolations.Interpolation1D:
    Linear, interpolate1d!, Interpolate1D, Flat, LinearExtrapolation

include("utils.jl")

function test_single_column(
    ::Type{DA},
    ::Type{FT},
    xminsource,
    xmaxsource,
    nsource,
    ntarget;
    xmintarget = xminsource,
    xmaxtarget = xmaxsource,
    extrapolation = Flat(),
    reverse = false,
) where {DA, FT}
    toler = FT(0.003)
    xsource, xtarget = get_uniform_column_grids(
        DA,
        FT,
        xminsource,
        xmaxsource,
        xmintarget,
        xmaxtarget,
        nsource,
        ntarget,
        reverse,
    )
    fsource = sin.(xsource) # function defined on source grid
    @testset "1D linear interpolation on single column with $FT" begin
        ftarget = DA(zeros(FT, ntarget)) # allocated function on target grid
        interpolate1d!(
            ftarget,
            xsource,
            xtarget,
            fsource,
            Linear(),
            extrapolation,
            reverse = reverse,
        )
        diff = maximum(
            abs.(ftarget .- sin.(xtarget)) .* (xtarget .≤ xmaxsource) .*
            (xtarget .≥ xminsource),
        )
        @test diff ≤ toler
        # test extrapolation
        test_extrapolation(
            (xminsource, xmaxsource),
            (xmintarget, xmaxtarget),
            xtarget,
            fsource,
            ftarget,
            extrapolation,
            reverse,
        )
    end
    @testset "1D linear interpolation, with broadcasting, on single column with $FT" begin
        itp = Interpolate1D(
            xsource,
            fsource,
            interpolationorder = Linear(),
            extrapolationorder = extrapolation,
            reverse = reverse,
        )
        ftarget = itp.(xtarget)
        diff = maximum(
            abs.(ftarget .- sin.(xtarget)) .* (xtarget .≤ xmaxsource) .*
            (xtarget .≥ xminsource),
        )
        @test diff ≤ toler
        # test extrapolation
        test_extrapolation(
            (xminsource, xmaxsource),
            (xmintarget, xmaxtarget),
            xtarget,
            fsource,
            ftarget,
            extrapolation,
            reverse,
        )
    end
    return nothing
end

function test_multiple_columns(
    ::Type{DA},
    ::Type{FT},
    xmin,
    xmax,
    nsource,
    ntarget,
    nlon,
    nlat;
    xmintarg = xmin,
    xmaxtarg = xmax,
    extrapolation = Flat(),
    reverse = false,
) where {DA, FT}
    @testset "1D linear interpolation on multiple columns with $FT on $DA" begin
        toler = FT(0.003)
        xsource, xtarget = get_uniform_column_grids(
            Array,
            FT,
            xmin,
            xmax,
            xmintarg,
            xmaxtarg,
            nsource,
            ntarget,
            reverse,
        )
        # allow a differnt source grid for each of the source columns 
        xsourcecols = DA(repeat(xsource, 1, nlon, nlat))
        # allow a different target grid for each of the target columns 
        xtargetcols = DA(repeat(xtarget, 1, nlon, nlat))
        fsourcecols = DA(sin.(xsourcecols))
        ftargetcols = DA(zeros(FT, ntarget, nlon, nlat))
        order = Linear()

        # interpolate with different source grid and target grids for all columns
        interpolate1d!(
            ftargetcols,
            xsourcecols, # different source grid for each source column
            xtargetcols, # different target grid for each target column
            fsourcecols,
            order,
            extrapolation,
            reverse = reverse,
        )
        diff = maximum(abs.(ftargetcols .- sin.(xtargetcols))[:])
        @test diff ≤ toler
        # interpolate with same source and target grids for all columns
        ftargetcols .= NaN
        interpolate1d!(
            ftargetcols,
            DA(xsource), # same source grid for all source columns
            DA(xtarget), # same target grid for all target columns
            fsourcecols,
            order,
            extrapolation,
            reverse = reverse,
        )
        diff = maximum(abs.(ftargetcols .- sin.(xtargetcols))[:])
        @test diff ≤ toler
        # interpolate with same source grid but different target grids for all columns
        ftargetcols .= NaN
        interpolate1d!(
            ftargetcols,
            DA(xsource), # same source grid for all source columns
            xtargetcols, # different target grid for all target columns
            fsourcecols,
            order,
            extrapolation,
            reverse = reverse,
        )
        diff = maximum(abs.(ftargetcols .- sin.(xtargetcols))[:])
        @test diff ≤ toler
        # interpolate with same target grid but different source grids for all columns
        ftargetcols .= NaN
        interpolate1d!(
            ftargetcols,
            xsourcecols, # different source grid for each source column
            DA(xtarget), # same target grid for all target columns
            fsourcecols,
            order,
            extrapolation,
            reverse = reverse,
        )
        diff = maximum(abs.(ftargetcols .- sin.(xtargetcols))[:])
        @test diff ≤ toler
    end
    return nothing
end

get_dims_singlecol(::Type{FT}) where {FT} = (FT(0), FT(2π), 150, 200)
get_dims_multicol(::Type{FT}) where {FT} = (FT(0), FT(2π), 150, 200, 1280, 640)
