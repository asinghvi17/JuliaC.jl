module StagedBuildOnly
function __init__()
    ccall(:puts, Cint, (Cstring,), "STAGED_BUILD_ONLY_INIT_RAN")
    nothing
end
end
