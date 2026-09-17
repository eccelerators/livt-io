#!/usr/bin/env python3
"""Characterize current UART RX with an independent serial peer and scoreboard."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from matrix import ROOT, harness


def main():
    work = ROOT / ".livt/uart-timing"
    work.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="receiver-", dir=work))
    src = run / "src"
    src.mkdir()
    for name in ("UartFrameFormat", "Uart", "UartReceiver", "UartTransmitter"):
        shutil.copy2(ROOT / "src/uart" / (name + ".lvt"), src)
    (src / "Root1000000.lvt").write_text(harness("Root1000000", "1000000Hz"))
    (run / "livt.toml").write_text('[project]\nname="ReceiverTolerance"\npath="src"\noutdir="out"\n')
    shutil.copy2(Path(__file__).with_suffix(".vhd"), run / "receiver.vhd")
    result = {"status": "running", "cases": [], "commands": [],
              "source_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sorted(src.glob("*.lvt"))},
              "harness_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in (Path(__file__), Path(__file__).with_suffix(".vhd"),
                                            Path(__file__).with_name("matrix.py"))},
              "tool_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in (Path.home() / ".livt/livt.jar",
                                        Path.home() / ".livt/extensions/livt-gen-vhdl.jar")}}

    def command(args, log):
        result["commands"].append(args)
        with (run / log).open("w") as output:
            return subprocess.run(["timeout", "60s", *args], cwd=run,
                                  stdout=output, stderr=subprocess.STDOUT).returncode

    try:
        for args, log in ((["livt", "build", "--project", str(run)], "build.log"),):
            if command(args, log):
                raise RuntimeError(f"Failed: {log}")
        files = sorted((run / "out/debug").glob("*/*.vhd"))
        if command(["ghdl", "-i", "--std=08", *map(str, files), "receiver.vhd"], "import.log"):
            raise RuntimeError("Failed: import.log")
        if command(["ghdl", "-m", "--std=08", "receiver_tolerance"], "elaborate.log"):
            raise RuntimeError("Failed: elaborate.log")
        for clock in (12000000, 100000000):
            for ppm in (-20000, 0, 20000):
                for phase in range(4):
                    for scenario in range(6):
                        log = f"rx-{clock}-{ppm}-{phase}-{scenario}.log"
                        code = command(["ghdl", "-r", "--std=08", "receiver_tolerance",
                                        f"-gCLOCK_HZ={clock}", f"-gPEER_PPM={ppm}",
                                        f"-gPHASE_QUARTERS={phase}", f"-gSCENARIO={scenario}",
                                        "--assert-level=error"], log)
                        passed = code == 0 and "UART_RECEIVER_PASS" in (run / log).read_text()
                        result["cases"].append({"clock_hz": clock, "baud_hz": 1000000,
                                                "peer_ppm": ppm, "phase_quarters": phase,
                                                "scenario": scenario, "exit_code": code,
                                                "status": "passed" if passed else "failed", "log": log})
                print(f"{clock} Hz, peer {ppm:+} ppm: checked", flush=True)
        result["status"] = "passed" if all(c["status"] == "passed" for c in result["cases"]) else "failed"
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        result.update(status="failed", error=str(error))
    finally:
        (run / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{result['status']}: {run / 'result.json'}")
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
