include("StagedNative.jl")
include("FilterProgram.jl")
using .StagedNative

variant = get(ARGS, 1, "baseline")
variant in ("baseline", "global", "global_reachable", "local", "package", "initok", "initfail") || error("unknown variant")
ENV["STAGED_VARIANT"] = variant
dir = joinpath(@__DIR__, "build", variant)
mkpath(dir)
ENV["STAGED_SETUP_LOG"] = joinpath(dir, "setup.log")
write(ENV["STAGED_SETUP_LOG"], "")
spec = ProgramSpec(name=:filter, setup=FilterProgram.setup, config=(rate=log(2.0),),
    instances=BakedPool(4), reset=FilterProgram.reset,
    exports=[ExportSpec(:step, FilterProgram.step, (Float64,); returns=Float64),
             ExportSpec(:value, FilterProgram.value, (); returns=Float64),
             ExportSpec(:checked, FilterProgram.checked, (Int32,); returns=Int32),
             ExportSpec(:clear, FilterProgram.clear, ())])
product = build(spec; source=joinpath(@__DIR__, "FilterProgram.jl"), output_dir=dir,
    project=joinpath(@__DIR__, "filter-env"))
println("PRODUCT=", product.library)
