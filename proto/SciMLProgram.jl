module SciMLProgram
using OrdinaryDiffEqTsit5
using OrdinaryDiffEqTsit5: SciMLBase
using StaticArrays
using DiffEqBase: DEVerbosity
import SciMLLogging

lorenz(u, p, t) = SVector(10.0 * (u[2]-u[1]), u[1]*(28.0-u[3])-u[2],
                          u[1]*u[2]-(8.0/3.0)*u[3])
struct LorenzState{I}
    integrator::I
end
function setup(config)
    prob = ODEProblem(lorenz, SVector(1.0, 0.0, 0.0), (0.0, config.stop))
    integrator = init(prob, Tsit5(); dt=0.001, adaptive=false,
        save_everystep=false, save_start=false, save_end=false,
        verbose=config.quiet ? DEVerbosity(SciMLLogging.None()) : DEVerbosity())
    LorenzState(integrator)
end
reset(s::LorenzState) = (reinit!(s.integrator); nothing)
function advance(s::LorenzState)::Float64
    solve!(s.integrator)
    SciMLBase.successful_retcode(s.integrator.sol) || throw(ErrorException("Lorenz solve failed"))
    s.integrator.u[1]
end
value(s::LorenzState)::Float64 = s.integrator.u[1]
time(s::LorenzState)::Float64 = s.integrator.t
end
