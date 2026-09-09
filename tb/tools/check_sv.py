"""Parse and elaborate all sources against REAL UVM with pyslang (no simulation).

python check_sv.py --uvm-home /path/to/uvm-core --python-deps /path/to/pyslang
The UVM library is intentionally not vendored into this learning project.
"""
import argparse
from pathlib import Path
import shlex
import sys


def source_arguments():
    sim = Path(__file__).resolve().parents[1] / "sim"
    arguments = []
    for line in (sim / "files.f").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith(("#", "//")):
            continue
        if line.startswith("+incdir+"):
            arguments += ["-I", (sim / line[8:]).resolve().as_posix()]
        else:
            arguments.append((sim / line).resolve().as_posix())
    return arguments


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uvm-home", type=Path, required=True)
    parser.add_argument("--python-deps", type=Path)
    args = parser.parse_args()
    if args.python_deps:
        sys.path.insert(0, str(args.python_deps.resolve()))
    from pyslang.driver import Driver
    uvm_src = args.uvm_home.resolve() / "src"
    if not (uvm_src / "uvm_pkg.sv").is_file():
        parser.error("--uvm-home must contain src/uvm_pkg.sv")
    driver = Driver()
    driver.addStandardArgs()
    driver.setTerminalColorsEnabled(False)
    arguments = ["slang", "--single-unit", "--top", "tb_top", "--timescale", "1ns/1ps",
                 "-I", uvm_src.as_posix(), "-D", "UVM_NO_DPI",
                 (uvm_src / "uvm_pkg.sv").as_posix(), *source_arguments()]
    command = " ".join(shlex.quote(arg) for arg in arguments)
    if not driver.parseCommandLine(command) or not driver.processOptions():
        return 1
    if not driver.parseAllSources():
        driver.reportParseDiags()
        return 1
    compilation = driver.createCompilation()
    driver.reportCompilation(compilation, False)
    success = driver.reportDiagnostics(False)
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
