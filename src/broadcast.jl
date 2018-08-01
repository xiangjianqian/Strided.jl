using Base.Broadcast: BroadcastStyle, AbstractArrayStyle, DefaultArrayStyle, Broadcasted

struct StridedArrayStyle{N} <: AbstractArrayStyle{N}
end

Broadcast.BroadcastStyle(::Type{<:StridedView{<:Any,N}}) where {N} = StridedArrayStyle{N}()

StridedArrayStyle(::Val{N}) where {N} = StridedArrayStyle{N}()
StridedArrayStyle{M}(::Val{N}) where {M,N} = StridedArrayStyle{N}()

Broadcast.BroadcastStyle(a::StridedArrayStyle, ::DefaultArrayStyle{0}) = a
Broadcast.BroadcastStyle(::StridedArrayStyle{N}, a::DefaultArrayStyle) where {N} = BroadcastStyle(DefaultArrayStyle{N}(), a)
Broadcast.BroadcastStyle(::StridedArrayStyle{N}, ::Broadcast.Style{Tuple}) where {N} = DefaultArrayStyle{N}()

function Base.similar(bc::Broadcasted{<:StridedArrayStyle{N}}, eltype::T) where {N,T}
    StridedView(similar(convert(Broadcasted{DefaultArrayStyle{N}}, bc), eltype))
end

function Base.copyto!(dest::StridedView{<:Any,N}, bc::Broadcasted{StridedArrayStyle{N}}) where {N}
    # convert to map

    # flatten and only keep the StridedView arguments
    # promote StridedView to have same size, by giving artificial zero strides
    stridedargs = promoteshape(size(dest), capturestridedargs(bc)...)

    let makeargs = make_makeargs(bc)
        f = @inline function(args::Vararg{Any,N}) where N
            bc.f(makeargs(args...)...)
        end
        return map!(f, dest, stridedargs...)
    end
end

promoteshape(sz::Dims, a1::StridedView, As...) = (promoteshape1(sz, a1), promoteshape(sz, As...)...)
promoteshape(sz::Dims) = ()
function promoteshape1(sz::Dims{N}, a::StridedView) where {N}
    newstrides = ntuple(Val(N)) do d
        if size(a, d) == sz[d]
            stride(a, d)
        elseif size(a, d) == 1
            0
        else
            throw(DimensionMismatch("array could not be broadcast to match destination"))
        end
    end
    return StridedView(a.parent, sz, newstrides, a.offset, a.op)
end

capturestridedargs(t::Broadcasted, rest...) = (capturestridedargs(t.args...)..., capturestridedargs(rest...)...)
capturestridedargs(t::StridedView, rest...) = (t, capturestridedargs(rest...)...)
capturestridedargs(t, rest...) = capturestridedargs(rest...)
capturestridedargs() = ()

const WrappedScalarArgs = Union{AbstractArray{<:Any,0}, Ref{<:Any}}

make_makeargs(bc::Broadcasted) = make_makeargs(()->(), bc.args)
@inline function make_makeargs(makeargs, t::Tuple{<:StridedView,Vararg{Any}})
    let makeargs = make_makeargs(makeargs, tail(t))
        return @inline function(head, tail::Vararg{Any,N}) where N
            (head, makeargs(tail...)...)
        end
    end
end
@inline function make_makeargs(makeargs, t::Tuple{<:WrappedScalarArgs,Vararg{Any}})
    let makeargs = make_makeargs(makeargs, tail(t))
        return @inline function(tail::Vararg{Any,N}) where N
            (t[1][], makeargs(tail...)...)
        end
    end
end
@inline function make_makeargs(makeargs, t::Tuple{Ref{Type{T}},Vararg{Any}}) where {T}
    let makeargs = make_makeargs(makeargs, tail(t))
        return @inline function(tail::Vararg{Any,N}) where N
            (T, makeargs(tail...)...)
        end
    end
end
@inline function make_makeargs(makeargs, t::Tuple{<:Any,Vararg{Any}})
    let makeargs = make_makeargs(makeargs, tail(t))
        return @inline function(tail::Vararg{Any,N}) where N
            (t[1], makeargs(tail...)...)
        end
    end
end
@inline function make_makeargs(makeargs, t::Tuple{<:Broadcasted,Vararg{Any}})
    bc = t[1]
    let makeargs = make_makeargs(makeargs, tail(t))
        let makeargs = make_makeargs(makeargs, bc.args)
            headargs, tailargs = Broadcast.make_headargs(bc.args), Broadcast.make_tailargs(bc.args)
            return @inline function(args::Vararg{Any,N}) where N
                args1 = makeargs(args...)
                a, b = headargs(args1...), tailargs(args1...)
                (bc.f(a...), b...)
            end
        end
    end
end
make_makeargs(makeargs, ::Tuple{}) = makeargs
