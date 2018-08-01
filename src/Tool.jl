##### Algebra #####

function col_normalize(A::Matrix, p::Real=2)
    return A / diagm([norm(A[:,n], p) for n=1:size(A,2)])
end

function col_normalize!(A::Matrix, p::Real=2)
    for n=1:size(A,2)
        A[:,n] /= norm(A[:,n], p)
    end
    return A
end

row_normalize(A) = col_normalize(A.')
row_normalize!(A) = col_normalize!(A.')


##### Wavelet transform #####

# Normalizations of Wavelets.jl for different families are not coherent:
# Assuming the sqrt(2) factor in the cascade algorithm (see wavefun), then the filters of the following
# family have to be rescaled by the corresponding factor
# - Daubechies: 1
# - Coiflet: 1
# - Symlet: 1/sqrt(2)
# - Battle-Lemarie: sqrt(2)
# - Beylkin: 1
# - Vaidyanathan: 1

"""
Construct the matrix of a convolution kernel h.
"""
function convolution_matrix(h::Vector{T}, N::Int) where T
    @assert N>0
    M = length(h)
    K = zeros(T, (M+N-1, M+N-1))
    for r=1:M
        for d=1:M+N-r
            K[d+r-1,d] = h[r]
        end
    end
    return K[:,1:N]
end


"""
Compute the scaling and the wavelet function using the cascade algorithm.

The implementation follows the reference 2, but with a modified initialization.

# Returns
* ϕ, ψ, g: scaling, wavelet function and the associated sampling grid (computed for the Daubechies wavelet)

# References
* https://en.wikipedia.org/wiki/Daubechies_wavelet
* https://en.wikipedia.org/wiki/Cascade_algorithm
* http://cnx.org/content/m10486/latest/
"""
function wavefunc(lo::Vector{Float64}, hi::Vector{Float64}=Float64[]; level::Int=10, nflag::Bool=true)
    if isempty(hi)
        hi = (lo .* (-1).^(1:length(lo)))[end:-1:1]
    else
        length(lo)==length(hi) || error("Invalid high-pass filter.")
    end

    # Initialization of the cascade algorithm
    # Method 1: using constant 1, this gives the best results (criteria of orthogonality etc.)
    ϕ = [1]
#
#     # Method 2: using the original filter
#     ϕ = copy(lo)
#
#     # Method 3: take one specific eigen vector of the decimated convolution matrix, see Reference 2.
#     K = convolution_matrix(lo, length(lo))[1:2:end, :]
#     μ, V = eig(K)  # such that (K * V) - V * diagm(μ) = 0
#     idx = find(abs.(μ - 1/sqrt(2)) .< 1e-3)[1]
#     ϕ = real(V[:, idx])

    # Normalization: this is necessary to get the correct numerical range
    ϕ /= sum(ϕ)
    ψ = Float64[]

    fct = sqrt(2)  # scaling factor

    # Iteration of the cascade algorithm
    for n = 1:level
        # up-sampling of low-pass filter
        s = 2^(n-1)
        l = (length(lo)-1) * s + 1
        lo_up = zeros(Float64, l)
        lo_up[1:s:end] = lo

        if n==level
            # Last iteration only
            # up-sampling of high-pass filter
            hi_up = zeros(Float64, l)
            hi_up[1:s:end] = hi
            ψ = conv(hi_up, ϕ) * fct
        end
        ϕ = conv(lo_up, ϕ) * fct
    end

    # sampling grid:
    # the Daubechies wavelet of N vanishing moments has support [0, 2N-1] and its qmf filter has length 2N
    g = (length(lo)-1) * collect(0:(length(ϕ)-1))/length(ϕ)

    if nflag # force unit norm
        δ = g[2]-g[1]  # step of the sampling grid
        ϕ /= sqrt(ϕ' * ϕ * δ)
        ψ /= sqrt(ψ' * ψ * δ)
    end

    return ϕ, ψ, g
end


"""
Compute the masks for convolution for a mode of truncation.

For a input signal `x` and a kernel `h`, the full convolution x*h has length `length(x)+length(h)-1`.
This function computes two masks:
- `kmask`: corresponds to the left/center/right part in x*h having the length of `x`
- `vmask`: corresponds to the valide coefficients (boundary free) in x*h

Note that `vmask` does not depend on `mode` and `vmask[kmask]` gives the mask of length of `x` corresponding
to the valid coefficients in `kmask`.

# Args
* nx: length of input signal
* nh: length of kernel
* mode: {:left, :right, :center}

# Returns
* kmask, vmask

# Examples
julia> y = conv(x, h)
julia> kmask, vmask = convmask(length(x), length(h), :center)
julia> tmask = vmask[kmask]
julia> y[kmask] # center part, same size as x
julia> y[vmask] # valide part, same as y[kmask][dmask]
"""
function convmask(nx::Int, nh::Int, mode::Symbol)
    kmask = zeros(Bool, nx+nh-1)

    if mode == :left
        kmask[1:nx] = true
    elseif mode == :right
        kmask[nh:end] = true  # or mask0[end-nx+1:end] = true
    elseif mode == :center
        m = max(1, div(nh, 2))
        kmask[m:m+nx-1] = true
    else
        error("Unknown mode: $mode")
    end

    vmask = zeros(Bool, nx+nh-1); vmask[nh:nx] = true
    return kmask, vmask
end


"""
Down-sampling operator.
"""
function downsampling(x::AbstractArray{<:Any, 1}, s::Int=2)
    return x[1:s:end]
end

"""
Up-sampling operator.
"""
function upsampling(x::AbstractArray{<:Any, 1}, s::Int=2; tight::Bool=true)
    y = zeros(length(x)*s)
    y[1:s:end] = x
    return tight ? y[1:(end-(s-1))] : y
end

↑ = upsampling  # \uparrow
↓ = downsampling  # \downarrow

# ∗(x,y) = conv(x,y[end:-1:1])  # correlation, \ast
∗(x,y) = conv(x,y)  # convolution, \ast
⊛(x,y) = ↓(x ∗ ↑(y, 2, tight=true), 2)  # up-down convolution, \circledast


"""
Compute filters of Wavelet Packet transform.

# Args
* lo: low-pass filter
* hi: high-pass filter
* n: level of decomposition. If n=0 the original filters are returned.

# Return
* a matrix of size ?-by-2^n that each column is a filter.
"""
function wpt_filter(lo::Vector{T}, hi::Vector{T}, n::Int) where T<:Number
    F0::Vector{Vector{T}}=[[1]]
    for l=1:n+1
        F1::Vector{Vector{T}}=[]
        for f in F0
            push!(F1, f ⊛ lo)
            push!(F1, f ⊛ hi)
        end
        F0 = F1
    end
    return hcat(F0...)
end


"""
N-fold convolution of two filters.

Compute
    x_0 ∗ x_1 ∗ ... x_{n-1}
where x_i ∈ {lo, hi}, i.e. either the low or the high filter.

# Return
* a matrix of size ?-by-(level+1) that each column is a filter.
"""
function biconv_filter(lo::Vector{T}, hi::Vector{T}, n::Int) where T<:Number
    @assert n>=0
    F0::Vector{Vector{T}}=[]
    for l=0:n+1
        s = reduce(∗, reduce(∗, [1], [hi for i=1:l]), [lo for i=l+1:n+1])
        push!(F0, s)
    end
    return hcat(F0...)
end


"""
Dyadic scale stationary wavelet transform using à trous algorithm.

# Returns
* ac: matrix of approximation coefficients with increasing scale index in column direction
* dc: matrix of detail coefficients
* mc: mask for valide coefficients
"""
function swt(x::Vector{Float64}, level::Int, lo::Vector{Float64}, hi::Vector{Float64}=Float64[];
        mode::Symbol=:center)
    @assert level > 0

    # if high pass filter is not given, use the qmf.
    if isempty(hi)
        hi = (lo .* (-1).^(1:length(lo)))[end:-1:1]
    else
        @assert length(lo) == length(hi)
    end

    nx = length(x)
    fct = 1  # unlike in the à trous algorithm of `wavefunc`, here the scaling factor must be 1.
    ac = zeros(Float64, (length(x), level))
    dc = zeros(Float64, (length(x), level))
    mc = zeros(Bool, (length(x), level))

    # Finest level transform
    nk = length(lo)
    km, vm = convmask(nx, nk, mode)
    xd = conv(hi, x) * fct
    xa = conv(lo, x) * fct
    ac[:,1], dc[:,1], mc[:,1] = xa[km], xd[km], vm[km]

    # Iteration of the cascade algorithm
    for n = 2:level
        # up-sampling of qmf filters
        s = 2^(n-1)
        l = (length(lo)-1) * s + 1
        lo_up = zeros(Float64, l)
        lo_up[1:s:end] = lo
        hi_up = zeros(Float64, l)
        hi_up[1:s:end] = hi
        nk += l-1  # actual kernel length

        km, vm = convmask(nx, nk, mode)
        xd = conv(hi_up, xa) * fct
        xa = conv(lo_up, xa) * fct
        ac[:,n], dc[:,n], mc[:,n] = xa[km], xd[km], vm[km]
    end

    return ac, dc, mc
end


"""
Vandermonde matrix.
"""
function vandermonde(dim::Tuple{Int,Int})
    nrow, ncol = dim
    V = zeros(Float64, dim)
    for c=1:dim[2]
        V[:,c] = collect((1:dim[1]).^(c-1))
    end
    return V
end

vandermonde(nrow::Int, ncol::Int) = vandermonde((nrow, ncol))


"""
Continuous wavelet transform based on quadrature.

# Args
* x: input signal
* wfunc: function for evaluation of wavelet at integer scales
"""
function cwt_quad(x::Vector{Float64}, wfunc::Function, sclrng::AbstractArray{Int}, mode::Symbol=:center)
    Ns = length(sclrng)
    Nx = length(x)

    dc = zeros((Nx, Ns))
    mc = zeros(Bool, (Nx, Ns))

    for (n,k) in enumerate(sclrng)
        f = wfunc(k)
        km, vm = convmask(Nx, length(f), mode)

        Y = conv(x, f[end:-1:1])
        dc[:,n] = Y[km] / sqrt(k)
        mc[:,n] = vm[km]
    end
    return dc, mc
end


"""
Evaluate the wavelet function at integer scales by looking-up table.

# Args
* k: scale
* ψ: compact wavelet function evaluated on a grid
* Sψ: support of ψ
* v: desired number of vanishing moments of ψ

# Return
f: the vector (ψ(n/k))_n such that n/k lies in Sψ.

# Note
For accuracy, increase the density of grid for pre-evaluation of ψ.
"""
function _intscale_wavelet_filter(k::Int, ψ::Vector{Float64}, Sψ::Tuple{Real,Real}, v::Int=0)
    # @assert k > 0
    # @assert Sψ[2] > Sψ[1]

    Nψ = length(ψ)
    dh = (Sψ[2]-Sψ[1])/Nψ  # sampling step
    # @assert k < 1/dh  # upper bound of scale range

    Imin, Imax = ceil(Int, k*Sψ[1]), floor(Int, k*Sψ[2])
    idx = [max(1, min(Nψ, floor(Int, n/k/dh))) for n in Imin:Imax]
    f::Vector{Float64} = ψ[idx]

    # Forcing vanishing moments: necessary to avoid inhomogenity due to sampling of ψ
    # Projection onto the kernel of a under-determined Vandermonde matrix:
    if v>0
        V = vandermonde((length(f), v))'
        f -= V\(V*f)
    end

    return f
end


function _intscale_wavelet_filter(k::Int, ψ::Function, Sψ::Tuple{Real,Real}, v::Int=0)
    # @assert k > 0
    # @assert Sψ[2] > Sψ[1]

    Imin, Imax = ceil(Int, k*Sψ[1]), floor(Int, k*Sψ[2])
    f::Vector{Float64} = ψ.((Imin:Imax)/k)

    # Forcing vanishing moments
    if v>0
        V = vandermonde((length(f), v))'
        f -= V\(V*f)
    end

    return f
end


function _intscale_haar_filter(k::Int)
    h = ones(Float64, 2*k)
    h[k+1:end] = -1.
    return h/sqrt(2)
end


"""
# Args
* v: number of vanishing moments
"""
function bspline_filters(k::Int, v::Int)
    @assert v>0
    lo = vcat(ones(k), ones(k))
    hi = vcat(ones(k),-ones(k))

    # return col_normalize(wpt_filter(lo, hi, v-1)) * sqrt(k)
    return col_normalize(biconv_filter(lo, hi, v-1)) * sqrt(k)
end


function _intscale_bspline_filter(k::Int, v::Int)
    @assert v>0
    hi = vcat(ones(k),-ones(k))
    # Analogy of the continuous case:
    # the l^2 norm of the rescaled filter ψ[⋅/k] is √k
    b0 = reduce(∗, [1], [hi for n=1:v])
    return normalize(b0) * sqrt(k)
end


"""
Continous Haar transform.
"""
function cwt_haar(x::Vector{Float64}, sclrng::AbstractArray{Int}, mode::Symbol=:center)
    return cwt_quad(x, _intscale_haar_filter, sclrng, mode)
end


"""
Continous B-Spline transform.

# TODO: parallelization
"""
function cwt_bspline(x::Vector{Float64}, sclrng::AbstractArray{Int}, v::Int, mode::Symbol=:center)
    # bsfilter = k->normalize(_intscale_bspline_filter(k, v))
    bsfilter = k->_intscale_bspline_filter(k, v)
    return cwt_quad(x, bsfilter, sclrng, mode)
end


mexhat(t::Real) = -exp(-t^2) * (4t^2-2t) / (2*sqrt(2π))

function _intscale_mexhat_filter(k::Int)
    return _intscale_wavelet_filter(k, mexhat, (-5.,5.), 2)  # Mexhat has two vanishing moments
end

"""
Continous Mexican hat transform
"""
function cwt_mexhat(x::Vector{Float64}, sclrng::AbstractArray{Int}, mode::Symbol=:center)
    return cwt_quad(x, _intscale_mexhat_filter, sclrng, mode)
end


# function cwt(x::Vector{Float64}, ψ::Vector{Float64}, Sψ::Real, level::Int, mode::Symbol=:center)
#     Nw = length(ψ)
#     Nx = length(X)
#     dh = Sψ/length(ψ)  # sampling step

#     dc = zeros((Nx, level))
#     mc = zeros(Bool, (Nx, level))

#     # H = Vector{Vector{Float64}}(Ns)
#     # Sh = zeros(Ns)

#     for k=1:level
#         idx = [max(1, min(Nw, floor(Int, n/k/dh))) for n in 1:(k*Sψ)]
#         h = ψ[idx]
#         h -= sum(h)/length(idx)  # forcing vanishing moments
#         km, vm = FracFin.convmask(Nx, length(h), mode)

#         #     Sh[k] = sum(h)
#         #     H[k] = h

#         Y = conv(X, h)
#         dc[:,k] = Y[km] / sqrt(k)
#         mc[:,k] = vm[km]
#     end
#     return dc, mc
# end


# """
# Stationary wavelet transform using à trous algorithm.

# # Returns
# * Ma: matrix of approximation coefficients with increasing scale index in row direction
# * Md: matrix of detail coefficients
# * nbem: number of left side boundary elements
# """
# function _swt_full(x::Vector{Float64}, level::Int, lo::Vector{Float64}, hi::Vector{Float64}=Float64[])
#     # @assert level > 0
#     # @assert length(lo) == length(hi)

#     # if high pass filter is not given, use the qmf.
#     if isempty(hi)
#         hi = (lo .* (-1).^(1:length(lo)))[end:-1:1]
#     end

#     ac = Array{Vector{Float64},1}(level)
#     dc = Array{Vector{Float64},1}(level)
#     klen = zeros(Int, level)  # length of kernels

#     # Finest level transform
#     ac[1] = conv(lo, x) * sqrt(2)
#     dc[1] = conv(hi, x) * sqrt(2)
#     klen[1] = length(lo)

#     # Iteration of the cascade algorithm
#     for n = 2:level
#         # up-sampling of qmf filters
#         s = 2^(n-1)
#         l = (length(lo)-1) * s + 1
#         lo_up = zeros(Float64, l)
#         lo_up[1:s:end] = lo
#         hi_up = zeros(Float64, l)
#         hi_up[1:s:end] = hi
#         klen[n] = l
#         dc[n] = conv(hi_up, ac[end]) * sqrt(2)
#         ac[n] = conv(lo_up, ac[end]) * sqrt(2)
#     end

#     nbem = cumsum(klen-1)  # number of the left side boundary elements (same for the right side)
#     return ac, dc, nbem
# end


# function conv_keep(x::Vector{Float64}, h::Vector{Float64}, mode::Symbol)
#     nx = length(x)
#     nh = length(h)
#     xh = conv(x, h)

#     mask = zeros(Bool, nx)
#     y = zeros(Float64, nx)

#     if mode == :L  # keep left
#         y = xh[1:nx]
#         mask[nh:end] = true
#     elseif mode == :R  # keep right
#         y = xh[end-nx+1:end]
#         mask[1:end-nh+1] = true
#     elseif mode == :C  # keep center
#         m = div(nh, 2)
#         y = xh[m:m+nx-1]
#         mask[nh-m+1:end-m+1] = true
#     end
#     return y, mask
# end


# function _keep_(y::AbstracArray{1}, nk::Int, mode::Symbol)
#     nx = length(y) - nk + 1  # size of original signal
#     mask = zeros(Bool, nx)

#     if mode == :L  # keep left
#         x = y[1:nx]
#         mask[nb] = true
#     elseif mode == :R  # keep right
#         y = x[end-nc+1:end]
#     elseif mode == :C  # keep center
#         m = div(nc, 2)
#         y = x[m:m+nc-1]
#     end
#     return y
# end

# function _keep_coeffs(ac::Array{Vector{Float64},1}, dc::Array{Vector{Float64},1}, klen::Vector{Int}, mode::Symbol)
#     level = length(ac)
#     ma = zeros(Float64, (level, length(x)))  # matrix of approximation coeffs
#     md = zeros(Float64, (level, length(x)))  # matrix of detail coeffs

#     for n = 1:level
#         if mode == :L  #
#         ma[n, :] = ac[n][nbem[n]+1:end-nbem[n]]
#         md[n, :] = dc[n][nbem[n]+1:end-nbem[n]]
#     end

#     return Ma, Md, mask
# end


# """
# Continuous wavelet transform using parametric wavelet.
# """
# function cwt(x::Vector{Float64}, lo::Vector{Float64}, level::Int)
#     @assert level>0

# #     xc = zeros(Float64, (level, length(x)))
#     ac::Array{Vector{Float64},1} = []
#     dc::Array{Vector{Float64},1} = []
#     klen = zeros(Int, level)

#     for n = 1:level
#         ϕ, ψ, g = wavefunc(lo, level=n, nflag=true)
#         push!(ac, conv(x, ϕ))
#         push!(dc, conv(x, ψ))
#         klen[n] = length(ϕ)
#     end
#     return ac, dc
# end

# """
# Morlet wavelet function.
# """
# function morlet()
# end

# """
# Mexican hat function.

# # Reference
# * https://en.wikipedia.org/wiki/Mexican_hat_wavelet
# """
# function mexhat(N::Int, a::Float64)
#     cst = 2 / (sqrt(3 * a) * (pi^0.25))
#     X = collect(0, N-1) - N/2
#     X = linspace(-3a, 3a, N)
#     return cst * (1 - (X/a).^2) .* exp(- (X/a).^2/2)
# end


##### Special functions #####

"""
Compute the continued fraction involved in the upper incomplete gamma function using the modified Lentz's method.
"""
function _uigamma_cf(s::Complex, z::Complex; N=100, epsilon=1e-20)
#     a::Complex = 0
#     b::Complex = 0
#     d::Complex = 0
    u::Complex = s
    v::Complex = 0
    p::Complex = 0

    for n=1:N
#         a, b = (n%2==1) ? ((-div(n-1,2)-s)*z, s+n) : (div(n,2)*z, s+n)
        a, b = (n%2==1) ? ((-div(n-1,2)-s), (s+n)/z) : (div(n,2), (s+n)/z)
        u = b + a / u
        v = 1/(b + a * v)
        d = log(u * v)
        (abs(d) < epsilon) ? break : (p += d)
#         println("$(a), $(b), $(u), $(v), $(d), $(p), $(exp(p))")
    end
    return s * exp(p)
end

doc"""
    uigamma0(z::Complex; N=100, epsilon=1e-20)

Upper incomplete gamma function with vanishing first argument:
$$ \Gamma(0,z) = \lim_{a\rightarrow 0} \Gamma(a,z) $$

Computed using the series expansion of the [exponential integral](https://en.wikipedia.org/wiki/Exponential_integral) $E_1(z)$.
"""
function uigamma0(z::Number; N=100, epsilon=1e-20)
    #     A::Vector{Complex} = [(-z)^k / k / exp(lgamma(k+1)) for k=1:N]
    #     s = sum(A[abs.(A)<epsilon])
    s::Complex = 0
    for k=1:N
        d = (-z)^k / k / exp(lgamma(k+1))
        (abs(d) < epsilon) ? break : (s += d)
    end
    r = -(eulergamma + log(z) + s)
    return (typeof(z) <: Real ? real(r) : r)
end

# """
# Upper incomplete gamma function.
# """
# function uigamma(a::Real, z::T; N=100, epsilon=1e-8) where {T<:Number}
#     z == 0 && return gamma(a)
#     u::T = z
#     v::T = 0
#     f::T = z
# #     f::Complex = log(z)
#     for n=1:N
#         an, bn = (n%2==1) ? (div(n+1,2)-a, z) : (div(n,2), 1)
#         u = bn + an / u
#         v = bn + an * v
#         f *= (u/v)
# #         f += (log(α) - log(β))
#         println("$(an), $(bn), $(u), $(v), $(f)")
#         if abs(u/v-1) < epsilon
#             break
#         end
#     end
#     return z^a * exp(-z) / f
# #     return z^a * exp(-z-f)
# end


doc"""
    uigamma(s::Complex, z::Complex; N=100, epsilon=1e-20)

Upper incomplete gamma function $\Gamma(s,z)$ with complex arguments.

Computed using the [continued fraction representation](http://functions.wolfram.com/06.06.10.0005.01).
The special case $\Gamma(0,z)$ is computed via the series expansion of the exponential integral $E_1(z)$.

# Reference
- [Upper incomplete gamma function](https://en.wikipedia.org/wiki/Incomplete_gamma_function)
- [Continued fraction representation](http://functions.wolfram.com/06.06.10.0005.01)
- [Exponential integral](https://en.wikipedia.org/wiki/Exponential_integral)
"""

function uigamma(s::Number, z::Number; N=100, epsilon=1e-20)
    if abs(s) == 0
        return uigamma0(z; N=N, epsilon=epsilon)
    end

    r = gamma(s) - z^s * exp(-z) / _uigamma_cf(Complex(s), Complex(z); N=N, epsilon=epsilon)
    return (typeof(s)<:Real && typeof(z)<:Real) ? real(r) : r
end

doc"""
    ligamma(s::Complex, z::Complex; N=100, epsilon=1e-20)

Lower incomplete gamma function $\gamma(s,z)$ with complex arguments.
"""
function ligamma(s::Number, z::Number; N=100, epsilon=1e-20)
    return gamma(s) - uigamma(s, z; N=N, epsilon=epsilon)
end


"""
Evaluate the Fourier transform of B-Spline wavelet.

# Args
* ω: frequency
* v: vanishing moments
"""
function bspline_ft(ω::Real, v::Int)
#     @assert v>0  # check vanishing moment
    return (ω==0) ? 0 : (2π)^((v-1)/2) * (-(1-exp(1im*ω/2))^2/(√2*1im*ω))^(v)
end


"""
Evaluate the integrand function of C^ψ_{H,ρ}

# Args
* ω: frequency
* v: vanishing moments
"""
function Cbspline_intfunc(τ::Real, ω::Real, ρ::Real, H::Real, v::Int)
#     @assert ρ>0
#     @assert 1>H>0
    return (ω==0) ? 0 : real(bspline_ft(sqrt(ρ)*ω, v) * conj(bspline_ft(ω/sqrt(ρ), v)) / abs(ω)^(2H+1) * exp(-1im*ω*τ))
end

"""
Evaluate the C^ψ_{H,ρ} function by numerical integration.

# Args
"""
function Cbspline_func(τ::Real, ρ::Real, H::Real, v::Int)
    f(ω) = Cbspline_intfunc(τ, ω, ρ, H, v)
    res = QuadGK.quadgk(f, -100, 100, order=10)
    return res[1]
end


"""
Evaluate matrix in DCWT
"""
function Cbspline_matrix(H::Real, v::Int, lag::Int, sclrng::AbstractArray)
    return [Cbspline_func(lag/sqrt(i*j), j/i, H, v) for i in sclrng, j in sclrng]
end
#     A = zeros((length(sclrng),length(sclrng)))

#     # Parallelization!
#     for (c,i) in enumerate(sclrng)
#         for (r,j) in enumerate(sclrng)
#             A[r,c] = Cbspline_func(lag/sqrt(i*j), sqrt(i*j), H, v)
#             # f(ω) = Cbspline_intfunc(lag/sqrt(i*j), ω, sqrt(i*j), H, v)
#             # res = QuadGK.quadgk(f, -20, 20)
#             # A[r,c] = res[1]
#         end
#     end
#     return A
# end