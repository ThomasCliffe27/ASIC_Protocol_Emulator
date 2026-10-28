"""Run every Testing/**/test_*.py suite and Testing/**/*_tb.sv testbench.

Usage: python Testing/test_all.py [--vivado-bin PATH] [--timeout SECONDS]
Vivado is located automatically. Build products and logs go in Testing/.test_all.
Each HDL testbench must have a top module matching its filename, print PASS on
success, and finish with $finish. Missing tools and incomplete simulations fail.
"""

import argparse
from collections.abc import Sequence
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
TESTING = ROOT / "Testing"
OUTPUT = TESTING / ".test_all"
HDL_ERROR = re.compile(r"^\s*(?:ERROR\b|FATAL\b|Fatal:|Error:)", re.MULTILINE | re.IGNORECASE)


def tool_in(directory: Path, name: str) -> Path | None:
    for suffix in ((".bat", ".exe", "") if os.name == "nt" else ("",)):
        candidate = directory / (name + suffix)
        if candidate.is_file():
            return candidate
    return None


def find_vivado(explicit: Path | None = None) -> dict[str, Path]:
    """Prefer an explicit install, then PATH/environment, then common installs."""
    names = ("xvlog", "xelab", "xsim")
    if explicit is not None:
        candidates = [explicit]
    else:
        candidates = []
        on_path = shutil.which("xvlog")
        if on_path:
            candidates.append(Path(on_path).parent)
        if os.environ.get("XILINX_VIVADO"):
            candidates.append(Path(os.environ["XILINX_VIVADO"]) / "bin")
        for base in (Path("C:/AMDDesignTools"), Path("C:/Xilinx"),
                     Path("/tools/Xilinx"), Path("/opt/Xilinx")):
            if base.is_dir():
                installs = list(base.glob("*/Vivado/bin")) + list(base.glob("Vivado/*/bin"))
                candidates.extend(sorted(installs, key=lambda p: tuple(
                    int(number) for number in re.findall(r"\d+", str(p))), reverse=True))
    for directory in candidates:
        directory = directory.resolve()
        tools: dict[str, Path] = {}
        for name in names:
            tool = tool_in(directory, name)
            if tool is None:
                break
            tools[name] = tool
        else:
            return tools
    raise RuntimeError("Cannot find xvlog, xelab and xsim. Use --vivado-bin <Vivado/bin>.")


def run_command(arguments: Sequence[str | Path], directory: Path,
                log: Path, timeout: float) -> str:
    """Capture each stage and stop only the runner's process tree on timeout."""
    command = [str(argument) for argument in arguments]
    with subprocess.Popen(command, cwd=directory, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                          errors="replace", start_new_session=sys.platform != "win32") as process:
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            if sys.platform == "win32":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.kill()
            output, _ = process.communicate()
            log.write_text(output, encoding="utf-8")
            raise RuntimeError(f"Timed out after {timeout:g}s; see {log}") from None
    log.write_text(output, encoding="utf-8")
    if process.returncode != 0 or HDL_ERROR.search(output):
        print(output[-6000:], flush=True)
        raise RuntimeError(f"Command failed (exit {process.returncode}); see {log}")
    return output


def run_python(test: Path, directory: Path, timeout: float) -> None:
    output = run_command(
        [sys.executable, "-B", "-m", "unittest", "discover", "-s", test.parent,
         "-p", test.name, "-v"], ROOT, directory / "python.log", timeout)
    if not re.search(r"Ran [1-9]\d* tests?\b", output):
        raise RuntimeError(f"No unittest cases ran; see {directory / 'python.log'}")
    print(output.rstrip(), flush=True)


def prepare_fixtures(test: Path, directory: Path, timeout: float) -> None:
    # Keep fixture regeneration inside the build directory, leaving checked-in
    # program images untouched. Both relative-to-ROM and relative-to-repo paths
    # are available to $readmemh in each isolated simulation working directory.
    fixtures = list(test.parent.iterdir())
    manifest = test.parent / "fixtures.txt"
    if manifest.is_file():
        fixtures.extend(ROOT / line.strip() for line in manifest.read_text().splitlines()
                        if line.strip() and not line.lstrip().startswith("#"))
    for fixture in sorted(fixtures):
        if not fixture.is_file() or fixture.suffix.lower() not in (".hex", ".mem", ".bin", ".dat", ".asm"):
            continue
        mirrored = directory / fixture.relative_to(ROOT)
        mirrored.parent.mkdir(parents=True, exist_ok=True)
        if fixture.suffix.lower() == ".asm":
            mirrored = mirrored.with_suffix(".hex")
            run_command([sys.executable, "-B", ROOT / "Assembler" / "assembler.py",
                         fixture, mirrored], ROOT, directory / f"assemble_{fixture.stem}.log", timeout)
        else:
            # An assembly source is authoritative when both formats exist.
            if fixture.suffix.lower() == ".hex" and fixture.with_suffix(".asm").exists():
                continue
            shutil.copy2(fixture, mirrored)
        shutil.copy2(mirrored, directory / mirrored.name)


def run_hdl(test: Path, directory: Path, tools: dict[str, Path], timeout: float) -> None:
    prepare_fixtures(test, directory, timeout)
    sources = sorted((ROOT / "Sources").rglob("*.sv"))
    run_command([tools["xvlog"], "--sv", *sources, test], directory,
                directory / "compile.log", timeout)
    snapshot = test.stem + "_all_tests"
    run_command([tools["xelab"], test.stem, "--snapshot", snapshot,
                 "--timescale", "1ns/1ps", "--mt", "off"], directory,
                directory / "elaborate.log", timeout)
    output = run_command([tools["xsim"], snapshot, "--runall"], directory,
                         directory / "simulate.log", timeout)
    # XSim sometimes exits zero after a simulator error. Require positive
    # completion evidence as well as checking its return code and diagnostics.
    passes = re.findall(r"^\s*PASS\b[^\r\n]*", output, re.MULTILINE)
    if not passes or "$finish called" not in output:
        print(output[-6000:], flush=True)
        raise RuntimeError(f"Simulation did not report PASS and $finish; see {directory / 'simulate.log'}")
    for line in passes:
        print(line.strip(), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vivado-bin", type=Path, help="Directory containing xvlog, xelab and xsim")
    parser.add_argument("--timeout", type=float, default=180,
                        help="Wall-clock timeout for each command (default: 180 seconds)")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")

    tests = sorted(path for pattern in ("test_*.py", "*_tb.sv")
                   for path in TESTING.rglob(pattern)
                   if path.resolve() != Path(__file__).resolve()
                   and not any(part.startswith(".") or part == "__pycache__"
                              for part in path.relative_to(TESTING).parts))
    if not tests:
        print("FAIL: No tests found in Testing.", flush=True)
        return 1

    tools: dict[str, Path] | None = None
    tool_error: str | None = None
    if any(test.suffix == ".sv" for test in tests):
        try:
            tools = find_vivado(args.vivado_bin)
            print(f"Vivado: {tools['xsim'].parent}", flush=True)
        except RuntimeError as error:
            tool_error = str(error)

    results = []
    for test in tests:
        name = test.relative_to(ROOT).as_posix()
        directory = OUTPUT / test.relative_to(TESTING).with_suffix("")
        directory.mkdir(parents=True, exist_ok=True)
        print(f"\nRUN {name}", flush=True)
        started = time.monotonic()
        try:
            if test.suffix == ".py":
                run_python(test, directory, args.timeout)
            else:
                if tools is None:
                    raise RuntimeError(tool_error or "Vivado tools are unavailable.")
                run_hdl(test, directory, tools, args.timeout)
            passed, detail = True, ""
        except (OSError, RuntimeError) as error:
            passed, detail = False, str(error)
        results.append((name, passed, time.monotonic() - started, detail))

    print("\nTest summary", flush=True)
    for name, passed, elapsed, detail in results:
        print(f"{'PASS' if passed else 'FAIL'}  {name} ({elapsed:.1f}s)", flush=True)
        if detail:
            print(f"      {detail}", flush=True)
    failed = sum(not result[1] for result in results)
    print(f"\n{len(results) - failed}/{len(results)} suites passed. Logs: {OUTPUT}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nTests interrupted.", file=sys.stderr)
        sys.exit(130)
