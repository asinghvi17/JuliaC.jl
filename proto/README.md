# Staged native program experiment

Tested on Linux x86_64, Julia **1.12.7**, JuliaC **0.3.12** (checkout base
`98e8286`), PackageCompiler **2.4.1**, with GCC and `cpu_target="native"`.
All dependencies resolved from the installed cache, with `JULIA_PKG_OFFLINE=true`;
no downloads, pushes, or GitHub operations were needed. JuliaC's initial load
failed because its project had no manifest; offline `Pkg.instantiate()` fixed it.

`StagedNative.jl` implements `ProgramSpec`, `ExportSpec`, `BakedPool`, source/header
generation, and JuliaC's compile → link → optional bundle recipes. `build_filter.jl`
is a complete example. Each build leaves `build/<variant>/build.jl`, `program.h`,
`abi.json`, `image.o.a`, and `libfilter.so`, plus compiler/setup/C-test logs.
`results/` records the measured run; `locks/` records dependency versions. Large
binaries, depot caches, and the instantiated SciML environment are ignored.
`results/filter-build.jl` and `results/program.h` preserve a generated example;
the source snapshot's include path is made relative for checkout portability.

## Reproduce

From the checkout root (the second depot below supplies installed packages):

```bash
julia --version
export JULIA_DEPOT_PATH="$PWD/proto/.depot:${JULIA_DEPOT_PATH:-$HOME/.julia}"
export JULIA_PKG_OFFLINE=true
export JULIA_NUM_PRECOMPILE_TASKS=2
export JULIA_PKG_PRECOMPILE_AUTO=0
cp proto/locks/juliac.toml Manifest.toml
julia --startup-file=no --project=. -e 'using Pkg; Pkg.offline(true); Pkg.instantiate()'
python3 proto/run_experiments.py
```

The runner uses separate Julia processes for `baseline global local package
initok initfail global_reachable`, collects `stat`/`size`/`nm` and payload evidence,
compiles and runs each successful library's C harness, and writes
`proto/build/results.json`. The deliberately failing initializer is considered an
expected result only when its specific trim-verifier diagnostic appears. An
individual build and C test can be run as:

```bash
julia --startup-file=no --project=. proto/build_filter.jl baseline
gcc -std=c11 -Wall -Wextra -Werror -Iproto/build/baseline proto/filter_test.c \
    -Lproto/build/baseline -lfilter '-Wl,-rpath,$ORIGIN' -lm \
    -o proto/build/baseline/filter_test
proto/build/baseline/filter_test
size proto/build/baseline/libfilter.so
nm proto/build/baseline/libfilter.so
```

The recipe is exactly `ImageRecipe(file=generated_source,
output_type="--output-lib", trim_mode="safe", add_ccallables=true,
export_abi=abi_path, project=app_project, cpu_target="native")` →
`compile_products` → `LinkRecipe` → `link_products`. JuliaC forwards
`--output-incremental=no --strip-ir --strip-metadata --experimental --trim=safe`
to the image process. The generator itself and JuliaC are **not** included in the
generated source. Bundling is implemented as an option but was not exercised.
Measured sizes exclude libjulia, its shared dependencies, and any bundle.

## ABI and state

`setup(config)` is called four times at image-building top level. Its first return
value determines the concrete element type of the rooted `const STATES` vector.
The filter computes its coefficient using BigFloat, then retains only two Float64
fields. The generated `Base.@ccallable` functions return Int32 statuses and write
scalar results through pointers. Exports are prefixed (`filter_create`, etc.).

Handles are UInt64: `generation << 32 | one_based_slot`, with zero invalid.
Create reserves a baked slot and calls `reset`; destroy releases it and advances
the generation. A generation that wraps to zero permanently retires its slot.
Setup is never called by create/reset. A single host thread is required; callers
provide correctly aligned, writable pointers. Null is checked, arbitrary invalid
addresses are the caller's responsibility. Julia's ccallable entrypoints
auto-initialize/adopt the calling thread; the standalone C tests make no `jl_init`
call. Build-only initializers execute during that runtime initialization.

| Status | Meaning |
|---|---|
| 0 | success |
| 1 | invalid, inactive, or stale handle |
| 2 | pool exhausted |
| 3 | null output pointer |
| 4 | method/reset exception or return type mismatch |

Outputs are unchanged on failure. A throwing method can have partially mutated
its state. This prototype supports named module-level functions, fixed-width
integer/float scalar arguments/results, and a void result (`returns=Nothing`).
Configuration supports scalar literals, strings, symbols, tuples, and named
tuples. It does not transport arbitrary closures, IO, pointers, or resource-owning
graphs. Program authors must make successive setup calls produce independent
state. There is no WasmCodegen implementation or Wasm build in this experiment;
the spec, handle scheme and scalar ABI are candidates for reuse there.

## Image retention results

These are exact unstripped `.so` file sizes for one completed run, not deployment
footprints. Serialization/layout/debug information causes small run-to-run
variation; differences of a few KB do not establish that particular methods leak.

| Variant | `.so` bytes | trim=safe | C harness | 50 MB array payload |
|---|---:|---|---|---|
| baseline: BigFloat setup, no extra imports | 1,844,784 | pass | pass | absent |
| (i) global: 50 MB held by unused module global + imports | 1,860,384 | pass | pass | absent |
| (ii) local: 50 MB setup garbage + same imports | 1,847,880 | pass | pass | absent |
| (iii) package: Dates/Printf/TOML used only in setup | 1,847,544 | pass | pass | absent |
| initok: unused local package with trimmable `__init__` | 1,849,320 | pass | pass | absent |
| initfail: unused local package with dynamic `__init__` | no library | **fail** | not built | n/a |
| global_reachable: same array referenced by extra C entrypoint | 51,864,680 | pass | pass | **present** |
| SciML: quiet Lorenz integrators, pool=2 | 2,558,560 | pass | pass | n/a |

In (i), `FilterProgram.BuildOnly.BIG::Ref{Vector{UInt8}}` holds a **50,000,000-byte**
array. Each setup log line records `global_bytes=50000000 imaging=1`, establishing
that it is alive during image construction. No runtime export refers to the
binding. In (ii), each setup allocates a fresh array that is not returned or stored;
the generated source also runs `GC.gc(true)` after constructing the pool.
In all three comparisons, setup actually imports and calls Dates, Printf and TOML.
They are build-only dependencies, not just entries in the project file.

The payload scan looks for a unique marker immediately followed by 1,000 `Z`
bytes, rather than mistaking a surviving string constant for the array. It finds
no such payload in (i)/(ii)/(iii). The positive control adds a native entrypoint
that reads the array's length: it retains the marker plus approximately 50 MB of
`Z` data and grows `.data` from approximately 0.8 MB to 50.8 MB. This demonstrates
that an unused module binding is not enough to force this object into the trimmed
image, whereas a binding reachable from native code is.

The loaded stdlib names `Printf`, `Dates`, and `TOML` remain in the image (baseline
already contains `TOML`). They leave module/type metadata and a small size change.
`nm` finds no native `julia_setup_*`, `julia_scratch_*` or `julia_format_*` methods
in the comparison images. The evidence supports trimming the exercised ordinary
build-only methods; it does not prove that every piece of package metadata or all
possible package methods disappear. GMP/MPFR initialization symbols remain in
the baseline image too, so these are not binaries stripped of all BigFloat-related
runtime support.

Each successful filter harness verifies two independent accumulators, all four
pool slots, exhaustion, stale/zero/out-of-range/wrong-generation handles, reset
on reuse, null pointers, an exception leaving the output untouched, a void export,
and 1,000 destroy/create cycles. The setup log still contains exactly four
`imaging=1` calls after running C, from one image-process PID.

## Initializers are a separate root

The local fixtures in `fixtures/` are real packages with their own UUIDs and
projects. Only setup imports them; no runtime method references them.
`StagedBuildOnly.__init__` calls C `puts`. Its marker appears in the standalone
**runtime C test**, establishing that this build-only package's initializer was
retained and invoked again.

`StagedBuildOnlyBad.__init__` calls a function held in `Ref{Any}`. Compilation
fails before linking, with:

```text
Verifier error #1: unresolved call from statement
(Base.getfield(StagedBuildOnlyBad.CALLBACK, :x)::Any)(1.0)::Any
Stacktrace:
 [1] __init__()
   @ StagedBuildOnlyBad .../src/StagedBuildOnlyBad.jl:4
ERROR: LoadError: Failed to compile .../initfail/build.jl
```

Thus the image's module initialization list supplies trim entrypoints beyond the
declared program exports. Ordinary unreachable build-only code can disappear
while its module's `__init__` and the initializer's transitive code/data survive.
An initializer with an unresolved call can break safe trimming even though setup
was the only user of that package. No trim patch, initializer suppression or
`--trim=unsafe` was used to make this experiment pass.

## SciML probe

The optional dependencies were already available offline. The version lock uses
OrdinaryDiffEqTsit5 2.1.4, StaticArrays 1.9.20, OrdinaryDiffEqCore 4.17.0,
SciMLBase 3.53.1, DiffEqBase 7.20.1, and SciMLLogging 2.1.0.

```bash
mkdir -p proto/sciml-env proto/build
cp proto/locks/sciml-project.toml proto/sciml-env/Project.toml
cp proto/locks/sciml.toml proto/sciml-env/Manifest.toml
julia --startup-file=no --project=. proto/sciml_project.jl
julia --startup-file=no --project=. proto/build_sciml.jl --native
julia --startup-file=no --project=. proto/build_sciml.jl
gcc -std=c11 -Wall -Wextra -Werror -Iproto/build/sciml proto/sciml_test.c \
    -Lproto/build/sciml -llorenz '-Wl,-rpath,$ORIGIN' -lm \
    -o proto/build/sciml/sciml_test
proto/build/sciml/sciml_test
```

`SciMLProgram.jl` puts `init(ODEProblem(...), Tsit5())` in setup and `solve!` in an
export. It uses an out-of-place SVector Lorenz system, fixed `dt=0.001`, no saved
trajectory, and `DEVerbosity(SciMLLogging.None())`. The C harness confirms
`x(1)=-9.408450567062301` to 1e-8, an untouched second integrator, and reset to
`x(0)=1, t=0` on handle reuse. Native setup/solve/reset passes too. The export
checks the solver return code before reporting success.

The first attempt, with default solver verbosity, **failed** during safe trim
verification of runtime `solve!` → error reporting/logging, not during setup.
It emitted six diagnostics, including:

```text
trim verification not yet implemented for builtin `Core.invoke_in_world`
unresolved call ... (f::Function)(...::IOContext{IOBuffer}, ...::String)::Any
unresolved call ... Base.print(io::Any, ...::Any)::Any
```

The stacks reach DiffEqBase's `failure_message`/`report_integrator_failure`,
SciMLLogging, and `lorenz_advance`. After emitting them, that driver terminated
with SIGSEGV (shell exit 139); the cause of the driver crash was not investigated.
`results/sciml-default-verbosity.txt` preserves the short diagnostics. A follow-up
with `verbose=false` failed in setup because this solver version requires a
verbosity object. The final version uses the supported object API and passes
`--trim=safe` plus C execution, without patches to SciML or JuliaC. To try default
verbosity with the final source, pass `--default-verbosity` to `build_sciml.jl`;
it uses the same output directory, so it can overwrite the quiet build sources.

## Design conclusion

**Setup in the image process is workable for controlled programs.** The pool,
typed state, generation handles and status/out-pointer ABI work for both the
simple filter and this specifically configured SciML integrator. This experiment
does **not** show an unavoidable 50 MB leak merely because a build-only object is
held in an unused global. JuliaC safe trimming successfully discards that object
and the exercised ordinary setup code.

**It is not a general build-dependency isolation boundary.** Build-only package
initializers remain runtime roots, can retain code/data and side effects, and can
fail safe trimming. If the program interface promises arbitrary native build
tools without runtime contamination, use a separate setup producer plus a clean
image process that loads only runtime definitions/dependencies and reconstructs
or imports a validated state bundle. Merely launching the current image recipe
in a fresh process does not provide that separation; the setup imports happen
inside that process. Likewise, transferring state while re-importing the same
build-only packages in runtime definitions would preserve the problem.

For a constrained first implementation, this recipe can be offered with a clear
requirement that setup-loaded packages have acceptable, trimmable initializers.
Keep the ABI/spec independent of that staging policy. A transferred bundle needs
an explicit supported state format and resource rules; arbitrary Julia heap
serialization, including integrators, is not established here. Clean transfer
would not by itself fix trim errors in methods genuinely needed at runtime, such
as the default SciML logging path observed above.
