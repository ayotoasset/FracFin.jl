__precompile__()

module FracFin

# using Distributions
# using PDMats
# using StatsBase

using LinearAlgebra
using Statistics

import Base: convert, rand, length, size, show, binomial, getindex, promote_rule #, squeeze
import Distributions: VariateForm, Univariate, Multivariate, ValueSupport, Discrete, Continuous, Sampleable
import SpecialFunctions: gamma, lgamma
import DSP: conv, fft, ifft
import Dates

import Wavelets
# import Wavelets.WT.daubechies
# import Wavelets.Util.mirror

import DataFrames
import GLM
import QuadGK
import Optim
import ForwardDiff

import StatsBase
import StatsBase: autocov!, autocov
import Statistics: mean, cov

import LinearAlgebra: norm, pinv

import IterativeSolvers
import IterativeSolvers: lsqr

import Dates
import Dates:AbstractTime, AbstractDateTime, TimePeriod

import TimeSeries
import TimeSeries: TimeArray
import RCall

import PyCall
# @PyCall.pyimport pywt
# @PyCall.pyimport pywt.swt as pywt_swt
# @PyCall.pyimport pywt.iswt as pywt_iswt
const pywt = PyCall.PyNULL()

function __init__()
    copy!(pywt, PyCall.pyimport("pywt"))
end

import TimeSeries

"""
    Exception for not implemented methods.
"""
struct NotImplementedError <: Exception
    errmsg::AbstractString
    # errpos::Int64
end
show(io::IO, exc::NotImplementedError) = print(io, string("NotImplementedError:\n",exc.errmsg))

# export
#     # SamplingGrid.jl
#     TimeStyle,
#     ContinuousTime,
#     DiscreteTime,
#     SamplingGrid,
#     DiscreteTimeSamplingGrid,
#     ContinuousTimeSamplingGrid,
#     RegularGrid,
#     DiscreteTimeRegularGrid,
#     ContinuousTimeRegularGrid,
#     # StochasticProcess.jl
#     StochasticProcess,
#     ContinuousTimeStochasticProcess,
#     DiscreteTimeStochasticProcess,
#     SelfSimilarProcess,
#     StationaryProcess,
#     ContinuousTimeStationaryProcess,
#     DiscreteTimeStationaryProcess,
#     IncrementProcess,
#     FractionalIntegrated,
#     FractionalGaussianNoise,
#     FractionalBrownianMotion,
#     FARIMA,
#     autocov,
#     autocov!,
#     covmat,
#     covseq,
#     partcorr,
#     partcorr!,
#     # Sampler.jl
#     CholeskySampler,
#     LevinsonDurbin,
#     HoskingSampler,
#     CircSampler,
#     # CRMDSampler,
#     # WaveletSampler,
#     rand,
#     rand!,
#     rand_otf,
#     rand_otf!
#     # rand_rfn


include("Common.jl")
include("SamplingGrid.jl")
include("StochasticProcess.jl")
include("Sampler.jl")

include("Tool.jl")
include("CHA.jl")
include("Stat.jl")        
include("Estimator.jl")

end # module
