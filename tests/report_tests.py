"""Check AcTa's report contract with real CBMC and deliberately bad output."""

import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

PLUGIN = str(Path(sys.argv[1]).resolve())

with tempfile.TemporaryDirectory(prefix="acta report ") as directory:
    root = Path(directory)
    source = root / "input with spaces.c"
    harness = root / "harness with spaces.c"
    report_path = root / "verification report.json"
    raw = root / "cbmc output.json"

    def run(code, *, unwind=10, cbmc="cbmc", extras=(), harness_path=harness):
        source.write_text(code)
        report_path.write_text('{"status":"passed","stale":true}')
        command = [
            "frama-c", "-no-autoload-plugins", "-load-module", PLUGIN,
            "-acta", "-main", "compute", "-acta-run-cbmc", "-acta-report", str(report_path),
            "-acta-out", str(harness_path), "-acta-cbmc-out", str(raw),
            "-acta-cbmc-path", str(cbmc), "-acta-cbmc-unwind", str(unwind),
            "-acta-cbmc-args", json.dumps(list(extras)), str(source),
        ]
        completed = subprocess.run(command, capture_output=True, text=True, timeout=30)
        result = json.loads(report_path.read_text())
        assert "stale" not in result, result
        assert result["schema_version"] == 1 and result["entry_point"] == "compute", result
        return completed, result

    good = "/*@ requires 0 <= x <= 10; ensures \\result == x + 1; */\nint compute(int x) { return x + 1; }\n"
    completed, result = run(good)
    assert completed.returncode == 0 and result["status"] == "passed", (completed, result)
    assert result["cbmc_exit_code"] == 0 and result["properties"] == result["proved"] > 0, result
    assert result["failed_properties"] == [] and isinstance(json.loads(raw.read_text()), list), result

    completed, result = run(good.replace("\\result == x + 1", "\\result == x + 2"))
    assert completed.returncode != 0 and result["status"] == "failed", (completed, result)
    assert result["cbmc_exit_code"] == 10 and result["failed_properties"], result

    loop = "/*@ requires 0 <= n <= 8; ensures \\result == n; */\nint compute(int n) { int i=0; while(i<n) ++i; return i; }\n"
    completed, result = run(loop, unwind=3)
    assert completed.returncode != 0 and any("unwind" in name for name in result["failed_properties"]), result
    completed, result = run(loop, unwind=12)
    assert completed.returncode == 0 and result["status"] == "passed", (completed, result)

    for code in ("int compute(int x) { return x; }\n",
                 "/*@ requires x >= 0; */\nint compute(int x) { return x; }\n",
                 "/*@ predicate positive(integer x) = x > 0; */\n"
                 "/*@ requires positive(x); ensures \\result == x; */\nint compute(int x) { return x; }\n"):
        completed, result = run(code)
        assert completed.returncode != 0 and result["status"] == "error", (completed, result)

    fake = root / "fake cbmc"
    property = {"property": "acta_harness_compute.assertion.1", "description": "ensures", "status": "SUCCESS"}
    cases = [
        ("invalid JSON", 0),
        (json.dumps([{"cProverStatus": "success"}, {"result": []}]), 0),
        (json.dumps([{"cProverStatus": "success"}, {"result": [dict(property, property="helper.assertion.1")]}]), 0),
        (json.dumps([{"cProverStatus": "success"}, {"result": [dict(property, status="UNKNOWN")]}]), 0),
        (json.dumps([{"cProverStatus": "success"}, {"result": [property]}]), 10),
    ]
    for output, exit_code in cases:
        fake.write_text(f"#!/usr/bin/python3\nprint({output!r})\nraise SystemExit({exit_code})\n")
        fake.chmod(stat.S_IRWXU)
        completed, result = run(good, cbmc=fake)
        assert completed.returncode != 0 and result["status"] != "passed", (completed, result)

    for option in ("--function", "--no-assertions", "--property", "--partial-loops", "--depth",
                   "--no-unwinding-assertions", "--show-properties", "other.c", "--xml-ui"):
        completed, result = run(good, extras=[option])
        assert completed.returncode != 0 and result["status"] == "error", (option, result)
        assert not raw.exists(), "invalid options must stop before CBMC"

    completed, result = run(good, cbmc=root / "missing cbmc")
    assert completed.returncode != 0 and result["status"] == "error", (completed, result)

    completed, result = run(good, harness_path=root / "missing directory" / "harness.c")
    assert completed.returncode != 0 and result["status"] == "error", (completed, result)

    # Reject collisions before cleanup or error reporting can change the input.
    alias = root / "input alias.c"
    alias.symlink_to(source)
    hardlink = root / "input hardlink.c"
    os.link(source, hardlink)
    for option, destination in (
        ("-acta-report", source), ("-acta-out", source), ("-acta-cbmc-out", source),
        ("-acta-report", alias), ("-acta-report", hardlink), ("-acta-report", harness),
    ):
        source.write_text(good)
        completed = subprocess.run([
            "frama-c", "-no-autoload-plugins", "-load-module", PLUGIN,
            "-acta", "-main", "compute", "-acta-run-cbmc", "-acta-report", str(report_path),
            "-acta-out", str(harness), "-acta-cbmc-out", str(raw),
            option, str(destination), str(source),
        ], capture_output=True, text=True, timeout=30)
        assert completed.returncode != 0 and source.read_text() == good, (option, completed)
        assert "Output paths must be distinct" in completed.stdout + completed.stderr, completed

    # The legacy runner must propagate failures too, including paths with spaces.
    fake.write_text("#!/bin/sh\nexit 10\n")
    completed = subprocess.run([
        "frama-c", "-no-autoload-plugins", "-load-module", PLUGIN, "-acta", "-main", "compute",
        "-acta-run-cbmc", "-acta-out", str(harness), "-acta-cbmc-out", str(raw),
        "-acta-cbmc-path", str(fake), str(source),
    ], capture_output=True, text=True, timeout=30)
    assert completed.returncode != 0, completed

print("AcTa report checks passed.")
