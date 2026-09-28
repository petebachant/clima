import ClimaInterpolations.BilinearInterpolation: Bilinear, interpolatebilinear!
include("utils.jl")
using Test

testfunc(x, y) = sin(π * x) * cos(π * y)
testfunc(x, y, z) = sin(π * x) * cos(π * y) * z

function test_single_level(
    ::Type{DA},
    ::Type{FT},
    (xmin, xmax),
    (ymin, ymax),
    (nsourcex, nsourcey),
    (ntargetx, ntargety);
    toler,
) where {DA, FT}
    trial_constructor = nothing
    trial_interpolator = nothing
    @testset "bilinear interpolation on single level with $FT, nsource = ($nsourcex, $nsourcey), ntarget = ($ntargetx, $ntargety)" begin
        # build source and target mesh
        xsource, xtarget = get_uniform_column_grids(
            DA,
            FT,
            xmin,
            xmax,
            xmin,
            xmax,
            nsourcex,
            ntargetx,
        )
        ysource, ytarget = get_uniform_column_grids(
            DA,
            FT,
            ymin,
            ymax,
            ymin,
            ymax,
            nsourcey,
            ntargety,
        )
        bilinear = Bilinear(xsource, ysource, xtarget, ytarget)
        # build fsource
        xsourcecpu, ysourcecpu = Array(xsource), Array(ysource)
        sourcemesh = (
            x = DA([xsourcecpu[i] for i in 1:nsourcex, j in 1:nsourcey]),
            y = DA([ysourcecpu[j] for i in 1:nsourcex, j in 1:nsourcey]),
        )
        xtargetcpu, ytargetcpu = Array(xtarget), Array(ytarget)
        targetmesh = (
            x = DA([xtargetcpu[i] for i in 1:ntargetx, j in 1:ntargety]),
            y = DA([ytargetcpu[j] for i in 1:ntargetx, j in 1:ntargety]),
        )
        fsource = testfunc.(sourcemesh.x, sourcemesh.y)
        ftargetexact = testfunc.(targetmesh.x, targetmesh.y)
        # allocate ftarget
        ftarget = DA{FT}(undef, ntargetx, ntargety)
        # use bilinear interpolation
        interpolatebilinear!(ftarget, bilinear, fsource)
        l∞error = maximum(abs.((ftarget .- ftargetexact)[:]))
        @test l∞error ≤ toler
    end
    return (trial_constructor, trial_interpolator)
end

function test_multilevel(
    ::Type{DA},
    ::Type{FT},
    (xmin, xmax),
    (ymin, ymax),
    (zmin, zmax),
    (nsourcex, nsourcey),
    (ntargetx, ntargety),
    nlevels;
    toler,
) where {DA, FT}
    @testset "bilinear interpolation on $nlevels levels with $FT, nsource = ($nsourcex, $nsourcey), ntarget = ($ntargetx, $ntargety)" begin
        # build source and target mesh
        xsource, xtarget = get_uniform_column_grids(
            DA,
            FT,
            xmin,
            xmax,
            xmin,
            xmax,
            nsourcex,
            ntargetx,
        )
        ysource, ytarget = get_uniform_column_grids(
            DA,
            FT,
            ymin,
            ymax,
            ymin,
            ymax,
            nsourcey,
            ntargety,
        )
        z, _ = get_uniform_column_grids(
            DA,
            FT,
            zmin,
            zmax,
            zmin,
            zmax,
            nlevels,
            nlevels,
        )
        bilinear = Bilinear(xsource, ysource, xtarget, ytarget)
        # build fsource
        xscpu, yscpu, zcpu = Array(xsource), Array(ysource), Array(z)
        fsource = testfunc.(
            DA([xscpu[j] for i in 1:nlevels, j in 1:nsourcex, k in 1:nsourcey]),
            DA([yscpu[k] for i in 1:nlevels, j in 1:nsourcex, k in 1:nsourcey]),
            DA([zcpu[i] for i in 1:nlevels, j in 1:nsourcex, k in 1:nsourcey]),
        )
        xtcpu, ytcpu = Array(xtarget), Array(ytarget)
        ftargetexact = testfunc.(
            DA([xtcpu[j] for i in 1:nlevels, j in 1:ntargetx, k in 1:ntargety]),
            DA([ytcpu[k] for i in 1:nlevels, j in 1:ntargetx, k in 1:ntargety]),
            DA([zcpu[i] for i in 1:nlevels, j in 1:ntargetx, k in 1:ntargety]),
        )
        # allocate ftarget
        ftarget = DA{FT}(undef, nlevels, ntargetx, ntargety)
        # use bilinear interpolation
        interpolatebilinear!(ftarget, bilinear, fsource)
        l∞error = maximum(abs.((ftarget .- ftargetexact)))
        @test l∞error ≤ toler
    end
    return nothing
end

get_dims_singlelevel(::Type{FT}) where {FT} =
    ((FT(0), FT(3π)), (FT(0), FT(2π)), (2560, 1280), (2400, 1200), FT(0.00005))
get_dims_multilevel(::Type{FT}) where {FT} = (
    (FT(0), FT(3π)),
    (FT(0), FT(2π)),
    (FT(0), FT(1)),
    (1280, 640),
    (1200, 600),
    128,
    FT(0.0002),
)
