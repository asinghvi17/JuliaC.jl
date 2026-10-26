#!/usr/bin/env python3
"""Reproduce isolated builds; preserve compiler errors and C output per variant."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PROTO = ROOT / "proto"
os.chdir(ROOT)
env = os.environ.copy()
env["JULIA_DEPOT_PATH"] = str(PROTO / ".depot") + ":" + env.get("JULIA_DEPOT_PATH", str(Path.home() / ".julia"))
env["JULIA_PKG_OFFLINE"] = "true"
env["JULIA_NUM_PRECOMPILE_TASKS"] = "2"
variants = sys.argv[1:] or ["baseline", "global", "local", "package", "initok", "initfail", "global_reachable"]
rows = []
for variant in variants:
    dest = PROTO / "build" / variant
    dest.mkdir(parents=True, exist_ok=True)
    cmd = ["julia", "--startup-file=no", "--project=.", "proto/build_filter.jl", variant]
    print("+", " ".join(cmd), flush=True)
    with (dest / "build.log").open("w") as log:
        result = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT)
    row = {"variant": variant, "trim": "PASS" if result.returncode == 0 else "FAIL"}
    build_log = (dest / "build.log").read_text()
    if result.returncode == 0:
        assert variant != "initfail", "expected the build-only initializer to fail safe trimming"
        lib = dest / "libfilter.so"
        row["so_bytes"] = lib.stat().st_size
        data = lib.read_bytes()
        marker = b"STAGED_BUILD_ONLY_50MB_SENTINEL_7cd9f31e"
        # The string constant can remain as metadata; marker followed by 1000
        # payload bytes specifically identifies the array, not the string.
        row["array_payload"] = marker + b"Z" * 1000 in data
        row["payload_Z_bytes"] = data.count(b"Z" * 1000) * 1000
        cc = ["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-I"+str(dest),
              str(PROTO / "filter_test.c"), "-L"+str(dest), "-lfilter",
              "-Wl,-rpath,$ORIGIN", "-lm", "-o", str(dest / "filter_test")]
        subprocess.run(cc, check=True)
        tested = subprocess.run([str(dest / "filter_test")], env=env, capture_output=True, text=True)
        (dest / "test.log").write_text(tested.stdout + tested.stderr)
        row["c_test"] = "PASS" if tested.returncode == 0 else "FAIL"
        row["runtime_init_marker"] = "STAGED_BUILD_ONLY_INIT_RAN" in tested.stdout
        setup_lines = (dest / "setup.log").read_text().splitlines()
        row["setup_calls"] = len(setup_lines)
        row["setup_in_image"] = len(setup_lines) == 4 and all(s.endswith("imaging=1") for s in setup_lines)
        row["global_live_at_setup"] = all("global_bytes=50000000" in s for s in setup_lines)
        row["size"] = subprocess.check_output(["size", str(lib)], text=True).strip().splitlines()[-1].split()[:4]
        symbols = subprocess.check_output(["nm", str(lib)], text=True)
        row["setup_native_code"] = bool(re.search(r"\bt\s+julia_setup_", symbols))
        row["scratch_native_code"] = bool(re.search(r"\bt\s+julia_scratch_", symbols))
        row["format_native_code"] = bool(re.search(r"\bt\s+julia_format_", symbols))
        row["stdlib_names_in_image"] = [name for name in ["Printf", "Dates", "TOML"] if name.encode() in data]
        assert row["c_test"] == "PASS" and row["setup_in_image"], row
        assert row["array_payload"] == (variant == "global_reachable"), row
        assert row["runtime_init_marker"] == (variant == "initok"), row
        assert row["global_live_at_setup"] == (variant in ["global", "global_reachable"]), row
    else:
        row["c_test"] = "not built"
        row["expected_init_failure"] = variant == "initfail" and all(s in build_log for s in [
            "Verifier error #1: unresolved call", "StagedBuildOnlyBad.CALLBACK", "__init__()"])
        print(build_log[-6000:], flush=True)
    print(json.dumps(row), flush=True)
    rows.append(row)
(PROTO / "build" / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
if any(r["trim"] == "FAIL" and not r.get("expected_init_failure") for r in rows):
    sys.exit(1)
