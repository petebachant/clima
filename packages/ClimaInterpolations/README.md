# ClimaInterpolations.jl

A collection of interpolation tools for packages in the CliMA software ecosystem.

[![docsbuild][docs-bld-img]][docs-bld-url]
[![dev][docs-dev-img]][docs-dev-url]
[![ghaci][gha-ci-img]][gha-ci-url]
[![buildkite][bk-ci-img]][bk-ci-url]

[docs-bld-img]: https://github.com/CliMA/ClimaInterpolations.jl/workflows/Documentation/badge.svg
[docs-bld-url]: https://github.com/CliMA/ClimaInterpolations.jl/actions?query=workflow%3ADocumentation

[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://clima.github.io/ClimaInterpolations.jl/dev/

[gha-ci-img]: https://github.com/CliMA/ClimaInterpolations.jl/actions/workflows/ci.yml/badge.svg
[gha-ci-url]: https://github.com/CliMA/ClimaInterpolations.jl/actions/workflows/ci.yml

[bk-ci-img]: https://badge.buildkite.com/2a31b42d67409c27660a0dcce65b49294cd9c6b9f14c12f21e.svg/?branch=main
[bk-ci-url]: https://buildkite.com/clima/climainterpolations-ci

## Code Formatting with `JuliaFormatter.jl`

One of the tests consists in checking that the code is uniformly formatted. We
use [JuliaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl) to achieve
consistent formatting. Here's how to use it:

You can either install in your base environment with
``` sh
julia -e 'using Pkg; Pkg.add(name="JuliaFormatter", version="2.10.1")'
```
or use it from within the `TestEnv` (or base) environments (see previous section).

Then, you can format the package running:
``` julia
using JuliaFormatter; format(".")
```
or just with `format(".")` if the package is already imported.

The rules for formatting are defined in the `.JuliaFormatter.toml`.

If you are used to formatting from the command line instead of the REPL, you can
install `JuliaFormatter` in your base environment and call
``` sh
julia -e 'using JuliaFormatter; format(".")'
```
You could also define a shell alias
``` sh
alias julia_format_here="julia -e 'using JuliaFormatter; format(\".\")'"
```

> :note: Please, open an issue if you find workflow problems/friction with this
> system.
