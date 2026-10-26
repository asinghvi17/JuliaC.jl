# Resolve only installed package versions. No downloads for this optional probe.
using Pkg
Pkg.offline(true)
Pkg.activate(joinpath(@__DIR__, "sciml-env"))
Pkg.add([PackageSpec(name="OrdinaryDiffEqTsit5", version="2.1.4"),
         PackageSpec(name="StaticArrays", version="1.9.20"),
         PackageSpec(name="DiffEqBase", version="7.20.1"),
         PackageSpec(name="SciMLLogging", version="2.1.0")])
