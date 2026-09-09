"""Supplemental RTL-only simulation with Icarus; does NOT run UVM or SVA."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

TB = Path(__file__).resolve().parents[1]
PROJECT = TB.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog-dir", type=Path, help="directory containing iverilog and vvp executables")
    parser.add_argument("--seeds", default="1,7,42,2026")
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    try:
        seeds = list(dict.fromkeys(int(seed) for seed in args.seeds.split(",")))
        if not seeds or min(seeds) < 1:
            raise ValueError()
    except ValueError:
        parser.error("--seeds must be comma-separated positive integers")
    env = os.environ.copy()
    if args.iverilog_dir:
        env["PATH"] = str(args.iverilog_dir.resolve()) + os.pathsep + env.get("PATH", "")
    ivl = shutil.which("iverilog", path=env.get("PATH"))
    vvp = shutil.which("vvp", path=env.get("PATH"))
    if not ivl or not vvp:
        parser.error("iverilog and vvp must be available on PATH or in --iverilog-dir")
    results = TB / "sim/results"
    results.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("rtl_%Y%m%dT%H%M%SZ_")
    batch = Path(tempfile.mkdtemp(prefix=stamp, dir=results))
    records = []
    commands = []

    def execute(command, name):
        commands.append({"log": name, "argv": [str(value) for value in command]})
        try:
            proc = subprocess.run(command, cwd=batch, env=env, capture_output=True,
                                  text=True, errors="replace", timeout=args.timeout)
            log = proc.stdout + proc.stderr
            code = proc.returncode
        except subprocess.TimeoutExpired as exc:
            code, log = -1, f"WALL_TIMEOUT: {exc}"
        (batch / name).write_text(log, encoding="utf-8")
        return code, log

    try:
        execute([ivl, "-V"], "simulator_version.log")
        for fault in (False, True):
            build_name = "memory_fault" if fault else "clean"
            program = batch / f"{build_name}.vvp"
            command = [ivl, "-g2012", "-s", "rtl_selftest", "-o", str(program)]
            if fault:
                command.append("-DINJECT_ERROR")
            command += [str(PROJECT / "RTL/yapp_fifo.sv"), str(PROJECT / "RTL/yapp_router.sv"),
                        str(TB / "tools/rtl_selftest.sv")]
            code, log = execute(command, f"{build_name}_compile.log")
            if code != 0:
                records.append({"case": build_name + "_compile", "result": "FAIL", "exit_code": code})
                continue
            jobs = [("memory_fault", seeds[0], "HBUS_MISMATCH")] if fault else [
                *(("positive", seed, None) for seed in seeds), ("scoreboard_fault", seeds[0], "DATA_MISMATCH")]
            for case, seed, expected_error in jobs:
                command = [vvp, str(program), f"+SEED={seed}"]
                if case == "scoreboard_fault":
                    command.append("+NEGATIVE_SCOREBOARD")
                code, log = execute(command, f"{case}_s{seed}.log")
                if expected_error:
                    ok = code == 1 and expected_error in log and "RTL_SELFTEST_PASS" not in log
                    result = "EXPECTED_FAIL" if ok else "FAIL"
                else:
                    ok = code == 0 and "RTL_SELFTEST_PASS" in log and "FATAL" not in log
                    result = "PASS" if ok else "FAIL"
                records.append({"case": case, "seed": seed, "result": result, "exit_code": code,
                                "summary": "\n".join(line for line in log.splitlines()
                                                    if "RTL_SELFTEST_PASS" in line or "FATAL:" in line)})
                print(f"{result:14} {case} seed={seed}: {records[-1]['summary']}", flush=True)
    finally:
        (batch / "summary.json").write_text(json.dumps({"runs": records, "commands": commands}, indent=2), encoding="utf-8")
        print(f"RTL-only results: {batch}")
    return int(not records or any(record["result"] == "FAIL" for record in records))


if __name__ == "__main__":
    raise SystemExit(main())
