# ClimaInterpolations.jl

## Interpolation1D
`interpolate1d!` function can be used to perform linear interpolation on a single column on or a collection of columns. Both single threaded CPU and NVIDIA GPU platforms are supported. Examples for single column and multiple column cases are presented below.

### Example

Example for interpolating a single column on a CPU:

```julia
import ClimaInterpolations.Interpolation1D:
    Linear, interpolate1d!, Flat

FT, DA = Float32, Array
xminsource, xmaxsource, nsource, ntarget = FT(0), FT(2π), 150, 200
xmintarget, xmaxtarget = xminsource, xmaxsource

xsource = DA{FT}(range(xminsource, xmaxsource, length = nsource))
xtarget = DA{FT}(range(xmintarget, xmaxtarget, length = ntarget))

fsource = DA(sin.(xsource)) # function defined on source grid
ftarget = DA(zeros(FT, ntarget)) # allocated function on target grid
interpolate1d!(ftarget, xsource, xtarget, fsource, Linear(), Flat())
```

In-place interpolation is also supported on reverse (monotonically decreasing grids).
Please note that both the source and target grids need to be either monotonically
increasing (default, `reverse=false`) or monotonically decreasing (reverse=true).

```julia
# In-place interpolation on a reversed grid

import ClimaInterpolations.Interpolation1D:
    Linear, interpolate1d!, Flat

FT, DA = Float32, Array
xminsource, xmaxsource, nsource, ntarget = FT(0), FT(2π), 150, 200
xmintarget, xmaxtarget = xminsource, xmaxsource

xsource = DA{FT}(reverse(range(xminsource, xmaxsource, length = nsource)))
xtarget = DA{FT}(reverse(range(xmintarget, xmaxtarget, length = ntarget)))

fsource = DA(sin.(xsource)) # function defined on source grid
ftarget = DA(zeros(FT, ntarget)) # allocated function on target grid
interpolate1d!(ftarget, xsource, xtarget, fsource, Linear(), Flat(), reverse = true)
```

Example for interpolating multiple columns on a CPU:

```julia
import ClimaInterpolations.Interpolation1D:
    Linear, interpolate1d!, Flat

FT, DA = Float32, Array
xminsource, xmaxsource, nsource, ntarget, nlat, nlon = FT(0), FT(2π), 150, 200, 1280, 640
xmintarget, xmaxtarget = xminsource, xmaxsource

xsource = DA{FT}(range(xminsource, xmaxsource, length = nsource))
xtarget = DA{FT}(range(xmintarget, xmaxtarget, length = ntarget))

xsourcecols = DA(repeat(xsource, 1, nlon, nlat))
xtargetcols = DA(repeat(xtarget, 1, nlon, nlat))
fsourcecols = DA(sin.(xsourcecols))
ftargetcols = DA(zeros(FT, ntarget, nlon, nlat))

# interpolate with different source grid and target grids for all columns
interpolate1d!(ftargetcols, xsourcecols, xtargetcols, fsourcecols, Linear(), Flat())

# interpolate with same source and target grids for all columns
interpolate1d!(ftargetcols, xsource, xtarget, fsourcecols, Linear(), Flat())

# interpolate with same source grid but different target grids for all columns
interpolate1d!(ftargetcols, xsource, xtargetcols, fsourcecols, Linear(), Flat())

# interpolate with same target grid but different source grids for all columns
interpolate1d!(ftargetcols, xsourcecols, xtarget, fsourcecols, Linear(), Flat())
```

The above examples can be run on NVIDIA GPUs by setting `DA = CuArray`.

1D interpolation can also be invoked using a broadcasting call.

```julia
import ClimaInterpolations.Interpolation1D:
    Linear, Interpolate1D, interpolate1d!, Flat

FT, DA = Float32, Array
xminsource, xmaxsource, nsource, ntarget = FT(0), FT(2π), 150, 200
xmintarget, xmaxtarget = xminsource, xmaxsource

xsource = DA{FT}(range(xminsource, xmaxsource, length = nsource))
xtarget = DA{FT}(range(xmintarget, xmaxtarget, length = ntarget))

fsource = DA(sin.(xsource)) # function defined on source grid

itp = Interpolate1D(
        xsource,
        fsource,
        interpolationorder = Linear(),
        extrapolationorder = Flat(),
    )
ftarget = itp.(xtarget)
```

## BilinearInterpolation
`interpolatebilinear!` function can be used to perform bilinear interpolation on a single level on or a multiple horizontal levels of a rectangular grid. Both single threaded CPU and NVIDIA GPU platforms are supported. Examples for single level and multiple level cases are presented below.

### Example

Example for using bilinear interpolation a single level on a CPU:

```julia
# This example demonstrates use of bilinear interpolation for interpolating from 
# a source grid of dimension (nsourcex x nsourcey) to a target grid of dimension (ntargetx x ntargety)

import ClimaInterpolations.BilinearInterpolation: Bilinear, interpolatebilinear!
import ClimaInterpolations.Interpolation1D:
    Linear, interpolate1d!, Flat

FT, DA = Float32, Array

xminsource, xmaxsource, nsourcex, ntargetx = FT(0), FT(3π), 2560, 1280
xmintarget, xmaxtarget = xminsource, xmaxsource

ymin, ymax, nsourcey, ntargety = FT(0), FT(2π), 2400, 1200
ymintarget, ymaxtarget = ymin, ymax

xsource = DA{FT}(range(xminsource, xmaxsource, length = nsourcex))
xtarget = DA{FT}(range(xmintarget, xmaxtarget, length = ntargetx))

ysource = DA{FT}(range(ymin, ymax, length = nsourcey))
ytarget = DA{FT}(range(ymintarget, ymaxtarget, length = ntargety))

sourcemesh = (
    x = DA([xsource[i] for i in 1:nsourcex, j in 1:nsourcey]),
    y = DA([ysource[j] for i in 1:nsourcex, j in 1:nsourcey]),
) # Define function to be interpolated on the source grid


fsource = sin.(π .* sourcemesh.x) .* cos.(π .* sourcemesh.y) # function defined on source grid
ftarget = DA(zeros(FT, ntargetx, ntargety)) # allocated function on target grid

# Construct a `Bilinear` object containing the source and target grid information,
# and use it to perform the interpolation
bilinear = Bilinear(xsource, ysource, xtarget, ytarget)
interpolatebilinear!(ftarget, bilinear, fsource)
```

Example for using bilinear interpolation on multiple horizontal levels on a CPU:

```julia
# This example demonstrates use of multi-level bilinear interpolation for interpolating from 
# a source grid of dimension (nlevels x nsourcex x nsourcey) to a target grid of dimension (nlevels x ntargetx x ntargety)

import ClimaInterpolations.BilinearInterpolation: Bilinear, interpolatebilinear!
import ClimaInterpolations.Interpolation1D:
    Linear, interpolate1d!, Flat

FT, DA = Float32, Array

xminsource, xmaxsource, nsourcex, ntargetx = FT(0), FT(3π), 2560, 1280
xmintarget, xmaxtarget = xminsource, xmaxsource

ymin, ymax, nsourcey, ntargety = FT(0), FT(2π), 2400, 1200
ymintarget, ymaxtarget = ymin, ymax

zmin, zmax, nlevels = FT(0), FT(1), 128

xsource = DA{FT}(range(xminsource, xmaxsource, length = nsourcex))
xtarget = DA{FT}(range(xmintarget, xmaxtarget, length = ntargetx))

ysource = DA{FT}(range(ymin, ymax, length = nsourcey))
ytarget = DA{FT}(range(ymintarget, ymaxtarget, length = ntargety))

z = DA{FT}(range(zmin, zmax, length = nlevels))

# build a sample function defined on source grid for bilinear interpolation

sourcemesh = (
    x = DA([
        xsource[j] for i in 1:nlevels, j in 1:nsourcex,
        k in 1:nsourcey
    ]),
    y = DA([
        ysource[k] for i in 1:nlevels, j in 1:nsourcex,
        k in 1:nsourcey
    ]),
    z = DA([
        z[i] for i in 1:nlevels, j in 1:nsourcex, k in 1:nsourcey
    ]),
)


fsource = sin.(π .* sourcemesh.x) .* cos.(π .* sourcemesh.y) .* sourcemesh.z # function defined on source grid
ftarget = DA(zeros(FT, nlevels, ntargetx, ntargety)) # allocated function on target grid

# Construct a `Bilinear` object containing the source and target grid information,
# and use it to perform the interpolation
bilinear = Bilinear(xsource, ysource, xtarget, ytarget)
interpolatebilinear!(ftarget, bilinear, fsource)
```

The above examples can be run on NVIDIA GPUs by setting `DA = CuArray`.
