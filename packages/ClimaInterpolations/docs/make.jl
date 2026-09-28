import Documenter, DocumenterCitations
import ClimaInterpolations

bib = DocumenterCitations.CitationBibliography(joinpath(@__DIR__, "refs.bib"))

mathengine = Documenter.MathJax(
    Dict(
        :TeX => Dict(
            :equationNumbers => Dict(:autoNumber => "AMS"),
            :Macros => Dict(),
        ),
    ),
)

format = Documenter.HTML(
    prettyurls = !isempty(get(ENV, "CI", "")),
    mathengine = mathengine,
    collapselevel = 1,
)

Documenter.makedocs(;
    plugins = [bib],
    sitename = "ClimaInterpolations.jl",
    format = format,
    checkdocs = :exports,
    clean = true,
    doctest = true,
    modules = [ClimaInterpolations],
    pages = Any[
        "Home" => "index.md",
        "Interpolation1D.md",
        "BilinearInterpolation.md",
        "SplitTrilinearInterpolation.md",
        "references.md",
    ],
)

Documenter.deploydocs(
    repo = "github.com/CliMA/ClimaInterpolations.jl.git",
    target = "build",
    push_preview = true,
    devbranch = "main",
    forcepush = true,
)
