using MacroTools: @q

# TODO: `pure` functions should probably have type signatures, to avoid being
# over-general. For now this makes things convenient.

function purem(P, f)
  quote
    Mjolnir.abstract(::$(esc(P)), ::AType{typeof($(esc(f)))}, args::Const...) =
      Const($(esc(f))(map(arg -> arg.value, args)...))
    Mjolnir.abstract(::$(esc(P)), ::AType{typeof($(esc(f)))}, args...) =
      Core.Compiler.return_type($(esc(f)), Tuple{widen.(args)...})
  end
end

macro pure(P, fs)
  if isexpr(fs, :tuple)
    Expr(:block, [purem(P, f) for f in fs.args]...)
  else
    purem(P, fs)
  end
end

named(arg) = isexpr(arg, :(::)) && length(arg.args) == 1 ? :($(gensym())::$(arg.args[1])) : arg

typeless(x) = MacroTools.postwalk(x -> isexpr(x, :(::), :kw) ? x.args[1] : x, x)
isvararg(x) = isexpr(x, :(::)) && namify(x.args[2]) == :Vararg

function abstractm(ex, P, abstract)
  @capture(shortdef(ex), (name_(args__) = body_) |
                         (name_(args__) where {Ts__} = body_)) || error("Need a function definition")
  kw = length(args) > 1 && isexpr(args[1], :parameters) ? esc(popfirst!(args)) : nothing
  f, T = isexpr(name, :(::)) ?
    (length(name.args) == 1 ? (esc(gensym()), esc(name.args[1])) : esc.(name.args)) :
    (esc(gensym()), :(Core.Typeof($(esc(name)))))
  Ts == nothing && (Ts = [])
  args = named.(args)
  argnames = Any[typeless(arg) for arg in args]
  !isempty(args) && isvararg(args[end]) && (argnames[end] = :($(argnames[end])...,))
  args = esc.(args)
  argnames = esc.(argnames)
  Ts = esc.(Ts)
  fargs = kw == nothing ? [:($f::AType{<:$T}), args...] : [kw, :($f::AType{<:$T}), args...]
  quote
    f($(fargs...)) where $(Ts...) = $(esc(body))
    function Mjolnir.$abstract(::$P, $f::AType{<:$T}, $(args...)) where $(Ts...)
      f($f, $(argnames...))
    end
    nothing
  end
end

macro abstract(P, ex)
  abstractm(ex, P, :abstract)
end

macro partial(P, ex)
  abstractm(ex, P, :partial)
end
