push!(LOAD_PATH, joinpath(@__DIR__, "sciml-env"))
include("StagedNative.jl")
include("SciMLProgram.jl")
using .StagedNative

if "--native" in ARGS
    state = SciMLProgram.setup((stop=1.0, quiet=true))
    println("native x(1)=", SciMLProgram.advance(state), " t=", SciMLProgram.time(state))
    SciMLProgram.reset(state)
    @assert SciMLProgram.value(state) == 1.0 && SciMLProgram.time(state) == 0.0
else
    spec = ProgramSpec(name=:lorenz, setup=SciMLProgram.setup,
        config=(stop=1.0, quiet=!("--default-verbosity" in ARGS)),
        instances=BakedPool(2), reset=SciMLProgram.reset,
        exports=[ExportSpec(:advance, SciMLProgram.advance, (); returns=Float64),
                 ExportSpec(:value, SciMLProgram.value, (); returns=Float64),
                 ExportSpec(:time, SciMLProgram.time, (); returns=Float64)])
    product = build(spec; source=joinpath(@__DIR__, "SciMLProgram.jl"),
        output_dir=joinpath(@__DIR__, "build", "sciml"), project=joinpath(@__DIR__, "sciml-env"))
    println("PRODUCT=", product.library)
end
