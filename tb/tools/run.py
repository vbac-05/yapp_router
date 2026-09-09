"""Reproducible, fail-closed Xcelium runner. Python 3.10+, no third-party modules.

Run from any directory; output goes into a NEW results directory for each command.
No downloads, uploads, source edits, or automatic deletion are performed.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

TB = Path(__file__).resolve().parents[1]
PROJECT = TB.parent
SIM = TB / "sim"
UVM_REPORT = re.compile(r"^\s*(?:#\s*)?UVM_(ERROR|FATAL)\s+(?!\s*:)\S.*?\[([^\]]+)\]", re.M)
TOOL_ERROR = re.compile(r"\*[EF],|SVA_FAILURE|^\s*(?:#\s*)?(?:Error:|Fatal:|\*\*\s+(?:Error|Fatal):)", re.M)


def classify(log, returncode, expected_errors=(), timed_out=False):
    """A simulator exit code alone is NOT a UVM test result.

    Negative tests must reach TEST_FAIL and match only explicitly allowed UVM
    error IDs. Compilation errors, assertions, timeouts, and fatals never qualify.
    """
    if timed_out:
        return "FAIL", "wall-clock timeout"
    reports = UVM_REPORT.findall(log)
    fatal = [name for severity, name in reports if severity == "FATAL"]
    errors = [name for severity, name in reports if severity == "ERROR"]
    if fatal or TOOL_ERROR.search(log):
        return "FAIL", "fatal, assertion, or simulator error"
    if expected_errors:
        allowed = set(expected_errors)
        if ("[TEST_FAIL]" in log and "[TEST_PASS]" not in log and errors
                and set(errors) <= allowed and allowed <= set(errors)
                and returncode in (0, 1)):
            return "EXPECTED_FAIL", ", ".join(sorted(set(errors)))
        return "FAIL", "negative test did not produce exactly the required error IDs"
    # Also inspect summary counts: malformed/truncated reports cannot pass.
    nonzero_summary = re.search(r"UVM_(?:ERROR|FATAL)\s*:\s*[1-9]\d*", log)
    if returncode != 0 or errors or nonzero_summary or "[TEST_FAIL]" in log:
        return "FAIL", f"returncode={returncode}, UVM errors={errors}"
    if "[TEST_PASS]" not in log:
        return "FAIL", "missing TEST_PASS completion sentinel"
    return "PASS", "completed without reported errors"


def source_options():
    options, files = [], []
    for raw in (SIM / "files.f").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", "//")):
            continue
        if line.startswith("+incdir+"):
            options.append("+incdir+" + str((SIM / line[8:]).resolve()))
        else:
            path = (SIM / line).resolve()
            if not path.is_file():
                raise FileNotFoundError(path)
            files.append(path)
            options.append(str(path))
    return options, files


def source_hashes():
    # Capture include files too, and exclude generated results / confidential reference.
    paths = [PROJECT / "RTL/yapp_fifo.sv", PROJECT / "RTL/yapp_router.sv", SIM / "files.f"]
    for folder in ("common", "agents", "env", "interfaces", "ral", "sequences", "tests", "top"):
        paths.extend((TB / folder).glob("*.sv*"))
    paths.append(TB / "router_tb_pkg.sv")
    return {str(p.relative_to(PROJECT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def case_name(test):
    return test.get("id", test["name"])


def command_for(args, test, seed):
    sources, _ = source_options()
    command = [args.xrun, "-64bit", "-sv", "-uvmhome", str(args.uvm_home),
               "-timescale", "1ns/1ps", "-access", "+rwc", "-top", "tb_top",
               "-seed", str(seed), "-l", "simulator.log", *sources,
               f"+UVM_TESTNAME={test['name']}", f"+UVM_VERBOSITY={args.verbosity}"]
    if test.get("defines"):
        for define in test["defines"]:
            command += ["-define", define]
    if args.coverage:
        command += ["-coverage", "all", "-covtest", f"{test['name']}_s{seed}"]
    if args.waves:
        command.append("+DUMP_VCD")
    if args.no_coverage:
        command.append("+NO_COVERAGE")
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group()
    choice.add_argument("--test", default=None)
    choice.add_argument("--suite", choices=("smoke", "core", "negative", "extended", "all"))
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--seed", type=int, help="override the manifest seeds")
    parser.add_argument("--uvm-home", default=os.environ.get("UVMHOME"))
    parser.add_argument("--xrun", default="xrun")
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--verbosity", choices=("UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_FULL"), default="UVM_LOW")
    parser.add_argument("--coverage", action="store_true", help="enable simulator coverage database")
    parser.add_argument("--no-coverage", action="store_true", help="do not construct functional covergroups")
    parser.add_argument("--waves", action="store_true", help="write local VCD (can become large)")
    parser.add_argument("--dry-run", action="store_true", help="print commands; do not create result files")
    args = parser.parse_args()
    tests = json.loads((SIM / "regression.json").read_text(encoding="utf-8"))["tests"]
    if args.list:
        for test in tests:
            print(f"{case_name(test):36} suites={','.join(test['suites'])} seeds={test['seeds']}"
                  + (f" EXPECTED_FAIL={test['expected_errors']}" if test.get("expected_errors") else ""))
        return 0
    if not args.uvm_home:
        parser.error("Set UVMHOME or pass --uvm-home to a simulator-compatible UVM installation")
    args.uvm_home = Path(args.uvm_home).expanduser().resolve()
    if not args.dry_run and not (args.uvm_home / "src/uvm_pkg.sv").is_file():
        parser.error("UVMHOME must contain src/uvm_pkg.sv")
    if args.timeout <= 0 or (args.seed is not None and args.seed < 1):
        parser.error("timeout and seed must be positive")
    if not args.dry_run and not shutil.which(args.xrun):
        parser.error("xrun not found; use a licensed Xcelium host or --dry-run")
    if args.suite:
        selected = [t for t in tests if args.suite == "all" or args.suite in t["suites"]]
    else:
        selected = [t for t in tests if case_name(t) == (args.test or "router_smoke_test")]
    if not selected:
        parser.error("Unknown test; use --list")
    jobs = [(test, seed) for test in selected
            for seed in ([args.seed] if args.seed is not None else test["seeds"])]
    if args.dry_run:
        for test, seed in jobs:
            print(shlex.join(command_for(args, test, seed)))
        return 0
    results = SIM / "results"
    results.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ_")
    batch = Path(tempfile.mkdtemp(prefix=stamp, dir=results))
    summary = {"utc": stamp, "uvm_home": str(args.uvm_home), "source_sha256": source_hashes(), "runs": []}
    try:
        version = subprocess.run([args.xrun, "-version"], capture_output=True, text=True, timeout=30)
        summary["simulator_version"] = (version.stdout + version.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        summary["simulator_version"] = str(exc)
    for test, seed in jobs:
        run_dir = batch / f"{case_name(test)}_s{seed}"
        run_dir.mkdir()
        command = command_for(args, test, seed)
        (run_dir / "command.json").write_text(json.dumps(command, indent=2), encoding="utf-8")
        started = time.monotonic()
        timed_out = False
        with (run_dir / "console.log").open("w", encoding="utf-8") as output:
            try:
                proc = subprocess.run(command, cwd=run_dir, stdout=output, stderr=subprocess.STDOUT,
                                      timeout=args.timeout, text=True)
                code = proc.returncode
            except subprocess.TimeoutExpired:
                timed_out, code = True, -1
            except OSError as exc:
                output.write(str(exc))
                code = -1
        logs = (run_dir / "console.log").read_text(encoding="utf-8", errors="replace")
        if (run_dir / "simulator.log").is_file():
            logs += "\n" + (run_dir / "simulator.log").read_text(encoding="utf-8", errors="replace")
        result, reason = classify(logs, code, test.get("expected_errors", ()), timed_out)
        record = {"case": case_name(test), "test": test["name"], "seed": seed, "result": result, "reason": reason,
                  "exit_code": code, "seconds": round(time.monotonic() - started, 3), "directory": str(run_dir)}
        summary["runs"].append(record)
        (batch / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(f"{result:14} {case_name(test)} seed={seed}: {reason}", flush=True)
    print(f"Results: {batch}")
    return int(any(run["result"] == "FAIL" for run in summary["runs"]))


if __name__ == "__main__":
    sys.exit(main())
