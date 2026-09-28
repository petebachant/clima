module ClimaInterpolationsCUDAExt

using CUDA

import ClimaInterpolations
import ClimaInterpolations.Interpolation1D:
    interpolate,
    interpolate1d!,
    Interpolate1D,
    Order1D,
    Extrapolate1D,
    Linear,
    Flat,
    LinearExtrapolation,
    get_stencil

"""
    get_maxgridsize()

Returns the maximum allowed logical `CUDA` grid dimensions for the current device.
"""
function get_maxgridsize()
    device = CUDA.device()
    return (
        CUDA.attribute(device, CUDA.DEVICE_ATTRIBUTE_MAX_GRID_DIM_X),
        CUDA.attribute(device, CUDA.DEVICE_ATTRIBUTE_MAX_GRID_DIM_Y),
        CUDA.attribute(device, CUDA.DEVICE_ATTRIBUTE_MAX_GRID_DIM_Z),
    )
end

include(joinpath("cuda", "interpolation1d.jl"))
include(joinpath("cuda", "bilinearinterpolation.jl"))
end # module
