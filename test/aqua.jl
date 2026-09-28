using Test
using ClimaInterpolations
using Aqua

@testset "Aqua tests (performance)" begin
    # Persistent_tasks seems to give false negatives with Julia 1.10
    Aqua.test_all(
        ClimaInterpolations,
        ambiguities = true,
        unbound_args = true,
        undefined_exports = true,
        project_extras = true,
        stale_deps = true,
        deps_compat = true,
        piracies = true,
        persistent_tasks = VERSION >= v"1.11",
    )
end
