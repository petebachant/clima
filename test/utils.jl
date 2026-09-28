get_uniform_column_grids(
    ::Type{DA},
    ::Type{FT},
    xminsource,
    xmaxsource,
    xmintarget,
    xmaxtarget,
    nsource,
    ntarget,
    reverse = false,
) where {DA, FT} =
    reverse ?
    (
        DA{FT}(range(xmaxsource, xminsource, length = nsource)),
        DA{FT}(range(xmaxtarget, xmintarget, length = ntarget)),
    ) :
    (
        DA{FT}(range(xminsource, xmaxsource, length = nsource)),
        DA{FT}(range(xmintarget, xmaxtarget, length = ntarget)),
    )

function test_extrapolation(
    (xminsource, xmaxsource),
    (xmintarget, xmaxtarget),
    xtarget,
    fsource,
    ftarget,
    extrapolation,
    reverse = false,
)
    if xmintarget < xminsource || xmaxtarget > xmaxsource
        xtargetcpu = typeof(xtarget) <: Array ? xtarget : Array(xtarget)
        fsourcecpu = typeof(fsource) <: Array ? fsource : Array(fsource)
        ftargetcpu = typeof(ftarget) <: Array ? ftarget : Array(ftarget)
        if extrapolation == Flat()
            left_boundary_pass = true
            right_boundary_pass = true
            fsourceleft = reverse ? fsourcecpu[end] : fsourcecpu[1]
            fsourceright = reverse ? fsourcecpu[1] : fsourcecpu[end]
            for i in 1:length(xtargetcpu)
                if xtargetcpu[i] < xminsource
                    left_boundary_pass = ftargetcpu[i] == fsourceleft
                end
                if xtargetcpu[i] > xmaxsource
                    right_boundary_pass = ftargetcpu[i] == fsourceright
                end
            end
            @testset "testing Flat extrapolation" begin
                @test left_boundary_pass
                @test right_boundary_pass
            end
        end
    end
    return nothing
end
