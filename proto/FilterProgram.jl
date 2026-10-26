module FilterProgram

module BuildOnly
const BIG = Ref(UInt8[])
const MARKER = "STAGED_BUILD_ONLY_50MB_SENTINEL_7cd9f31e"
function scratch()
    a = fill(UInt8(0x5a), 50_000_000)
    copyto!(a, 1, codeunits(MARKER), 1, sizeof(MARKER))
    a
end
end

# Positive control: make the global reachable from an actual native entrypoint.
# This extra export exists only in this diagnostic variant.
if get(ENV, "STAGED_VARIANT", "baseline") == "global_reachable"
    @eval Base.@ccallable function buildonly_payload_size(out::Ptr{UInt64})::Int32
        out == C_NULL && return Int32(3)
        unsafe_store!(out, UInt64(length(BuildOnly.BIG[])))
        Int32(0)
    end
end

mutable struct Filter
    decay::Float64
    value::Float64
end

function setup(config)
    variant = get(ENV, "STAGED_VARIANT", "baseline")
    if variant == "initok"
        # A real package, loaded only by setup, with no runtime references.
        @eval import StagedBuildOnly
    elseif variant == "initfail"
        @eval import StagedBuildOnlyBad
    end
    if variant in ("global", "global_reachable", "local", "package")
        # Loading and calling these is build-only; no runtime method uses them.
        @eval import Dates, Printf, TOML
        Base.invokelatest() do
            parsed = TOML.parse("coefficient = 0.5")
            @assert parsed["coefficient"] == 0.5
            @assert Dates.year(Dates.Date(2026, 1, 1)) == 2026
            @assert Printf.format(Printf.Format("%.1f"), 0.5) == "0.5"
        end
    end
    if variant in ("global", "global_reachable")
        isempty(BuildOnly.BIG[]) && (BuildOnly.BIG[] = BuildOnly.scratch())
    elseif variant == "local"
        scratch = BuildOnly.scratch()
        @assert scratch[end] == 0x5a
    end
    # This is after allocation: prove the global was alive at image generation.
    if haskey(ENV, "STAGED_SETUP_LOG")
        open(ENV["STAGED_SETUP_LOG"], "a") do io
            println(io, getpid(), " global_bytes=", length(BuildOnly.BIG[]),
                " imaging=", ccall(:jl_generating_output, Cint, ()))
        end
    end
    # BigFloat and MPFR are build tools here, not application state.
    decay = Float64(exp(-BigFloat(config.rate)))
    Filter(decay, 0.0)
end

reset(s::Filter) = (s.value = 0.0; nothing)
step(s::Filter, x::Float64)::Float64 = (s.value = s.decay * s.value + x)
value(s::Filter)::Float64 = s.value
function checked(s::Filter, x::Int32)::Int32
    x < 0 && throw(DomainError(x))
    x
end
clear(s::Filter) = reset(s)
end
