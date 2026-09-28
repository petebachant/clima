#=
using Revise; using TestEnv; TestEnv.activate(); include("test/runtests.jl")
=#
using Test
using ClimaInterpolations
using SafeTestsets
using Aqua

@safetestset "interpolation1d" begin
    include("interpolation1D.jl")

    for FT in (Float32, Float64)
        for reverse in (false, true)
            # single column linear interpolation tests without extrapolation
            test_single_column(
                Array,
                FT,
                get_dims_singlecol(FT)...,
                reverse = reverse,
            )
            # single column linear interpolation tests with Flat extrapolation
            xmin, xmax, nsource, ntarget = get_dims_singlecol(FT)
            test_single_column(
                Array,
                FT,
                xmin,
                xmax,
                nsource,
                ntarget,
                xmintarget = xmin - 1.0,
                xmaxtarget = xmax + 1.0,
                extrapolation = Flat(),
                reverse = reverse,
            )
            # multi-column linear interpolation tests without extrapolation
            xmin, xmax, nsource, ntarget, nlon, nlat = get_dims_multicol(FT)
            test_multiple_columns(
                Array,
                FT,
                xmin,
                xmax,
                nsource,
                ntarget,
                nlon,
                nlat,
                reverse = reverse,
            )
        end
    end
end

@safetestset "bilinear interpolation" begin
    include("bilinearinterpolation.jl")

    for FT in (Float32, Float64)
        # bilinear interpolation on a single level
        xrange, yrange, nsource, ntarget, toler = get_dims_singlelevel(FT)
        test_single_level(
            Array,
            FT,
            xrange,
            yrange,
            nsource,
            ntarget,
            toler = toler,
        )

        # bilinear interpolation on multiple levels
        xrange, yrange, zrange, nsource, ntarget, nlevels, toler =
            get_dims_multilevel(FT)
        test_multilevel(
            Array,
            FT,
            xrange,
            yrange,
            zrange,
            nsource,
            ntarget,
            nlevels,
            toler = toler,
        )

    end
end

@safetestset "split trilinear interpolation" begin
    include("split_trilinear_interpolation.jl")

    for FT in (Float32, Float64)
        for vreverse in (false, true)
            (h1min, h1max),
            (h2min, h2max),
            (vmin, vmax),
            (nh1source, nh2source),
            (nh1target, nh2target),
            (nvsource, nvtarget),
            toler = get_dims_split_trilinear(FT)

            test_split_trilinear(
                Array,
                FT,
                (h1min, h1max),
                (h2min, h2max),
                (vmin, vmax),
                (nh1source, nh2source),
                nvsource,
                (nh1target, nh2target),
                nvtarget,
                toler = toler,
                vreverse = vreverse,
            )
        end
    end
end
#! format: off
@safetestset "Aqua" begin @time include("aqua.jl") end
#! format: on
