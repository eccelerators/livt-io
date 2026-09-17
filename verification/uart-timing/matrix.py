#!/usr/bin/env python3
"""Compile current UART sources and verify independent serial timing with GHDL."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
CLOCKS = (12000000, 25000000, 50000000, 100000000, 125000000)
BAUDS = (9600, 115200, 921600, 1000000)


def harness(name, baud, parameter=""):
    baud_value = "115200Hz" if baud is None else baud
    return f"""namespace Livt.IO.TimingVerification
using Livt.IO
/** Wraps the UART while preserving externally observable byte/control pins. */
component {name}
{{
\tuart: Uart<UartDataBits.Eight, UartParity.None, UartStopBits.One, {baud_value}>
\t/** Forwards a compile-time baud configuration into the RX/TX hierarchy. */
\tnew(rx: in logic, tx: out logic, txValid: in logic, txByte: in logic[8],
\t\ttxActive: out logic, txDone: out logic, rxValid: out logic,
\t\trxByte: out logic[8], rxError: out logic{parameter})
\t{{
\t\tthis.uart = new Uart<UartDataBits.Eight, UartParity.None, UartStopBits.One, {baud_value}>(
\t\t\trx, tx, txValid, txByte, txActive, txDone, rxValid, rxByte, rxError)
\t}}
}}
"""


def main():
    work = ROOT / ".livt/uart-timing"
    work.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="matrix-", dir=work))
    src = run / "src"
    src.mkdir()
    for name in ("UartFrameFormat", "Uart", "UartReceiver", "UartTransmitter"):
        shutil.copy2(ROOT / "src/uart" / (name + ".lvt"), src)
    (run / "livt.toml").write_text('[project]\nname="UartTimingMatrix"\nversion="1.0.0"\npath="src"\noutdir="out"\n')
    for baud in BAUDS:
        # Exercise the omitted default and explicit component value arguments.
        (src / f"Root{baud}.lvt").write_text(harness(f"Root{baud}", None if baud == 115200 else f"{baud}Hz"))
    result = {"status": "running", "matrix": [], "boundary": [], "negative": [], "commands": [],
              "source_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sorted(src.glob("*.lvt"))},
              "harness_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in (Path(__file__), Path(__file__).with_name("serial.vhd"))},
              "local_tool_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in (Path.home() / ".livt/livt.jar",
                                              Path.home() / ".livt/extensions/livt-gen-vhdl.jar") if p.is_file()}}
    def command(args, log, cwd=run):
        result["commands"].append(args)
        with (run / log).open("w") as output:
            return subprocess.run(["timeout", "180s", *args], cwd=cwd, stdout=output,
                                  stderr=subprocess.STDOUT).returncode
    try:
        if command(["livt", "build", "--project", str(run)], "build.log"):
            raise RuntimeError("Matrix compilation failed; see build.log")
        template = Path(__file__).with_name("serial.vhd").read_text()
        instances = []
        for baud in BAUDS:
            instances.append(f"""rate_{baud}: if BAUD_HZ = {baud} generate
    dut: entity work.livt_io_timingverification_root{baud} port map (
        ctor_rx => rx, ctor_tx => tx, ctor_txvalid => tx_request,
        ctor_txbyte => x"55", ctor_txactive => tx_active, ctor_txdone => tx_done,
        ctor_rxvalid => rx_valid, ctor_rxbyte => rx_byte, ctor_rxerror => rx_error,
        ctor_lvt_context_in => context_value);
end generate;""")
        (run / "serial.vhd").write_text(template.replace("-- DUT_INSTANCES", "\n".join(instances)))
        files = sorted((run / "out/debug/lib").glob("*.vhd")) + sorted((run / "out/debug/main").glob("*.vhd"))
        if command(["ghdl", "-i", "--std=08", *map(str, files), "serial.vhd"], "import.log"):
            raise RuntimeError("GHDL import failed")
        if command(["ghdl", "-m", "--std=08", "serial_timing"], "elaborate.log"):
            raise RuntimeError("GHDL elaboration failed")
        for clock in CLOCKS:
            for baud in BAUDS:
                log = f"serial-{clock}-{baud}.log"
                code = command(["ghdl", "-r", "--std=08", "serial_timing",
                                f"-gCLOCK_HZ={clock}", f"-gBAUD_HZ={baud}", "--assert-level=error"], log)
                text = (run / log).read_text()
                ticks = max(1, (clock + baud // 2) // baud)
                passed = code == 0 and "UART_MATRIX_PASS" in text
                result["matrix"].append({"clock_hz": clock, "baud_hz": baud,
                    "ticks_per_bit": ticks, "baud_error_percent": (clock / ticks / baud - 1) * 100,
                    "status": "passed" if passed else "failed", "log": log,
                    "measurements": [line.split("UART_METRIC ", 1)[1]
                                     for line in text.splitlines() if "UART_METRIC " in line]})
                print(f"{clock} Hz / {baud} baud: {'passed' if passed else 'FAILED'}", flush=True)
        # Characterization, not an assertion that unsupported ratios must work.
        for ratio in range(1, 13):
            for phase in range(4):
                log = f"boundary-{ratio}-{phase}.log"
                code = command(["ghdl", "-r", "--std=08", "serial_timing",
                    f"-gCLOCK_HZ={ratio * 1000000}", "-gBAUD_HZ=1000000",
                    f"-gRX_PHASE_QUARTERS={phase}", "--assert-level=error"], log)
                passed = code == 0 and "UART_MATRIX_PASS" in (run / log).read_text()
                result["boundary"].append({"ticks_per_bit": ratio, "phase_quarters": phase,
                    "status": "passed" if passed else "failed", "log": log})
        for label, expression, parameter in (
            ("zero", "0Hz", ""), ("fractional", "0.5Hz", ""),
            ("negative", "-1Hz", "")):
            invalid = run / ("invalid-" + label)
            shutil.copytree(src, invalid / "src")
            shutil.copy2(run / "livt.toml", invalid)
            (invalid / "src/Invalid.lvt").write_text(harness("Invalid", expression, parameter))
            log = "invalid-" + label + ".log"
            code = command(["livt", "build", "--project", str(invalid)], log, cwd=invalid)
            text = (run / log).read_text().lower()
            diagnostic = {"zero": "context-ticks-per-frequency-invalid",
                          "fractional": "context-ticks-per-frequency-invalid",
                          "negative": "literal-not-convertible"}[label]
            rejected = code not in (0, 124) and f"[{diagnostic}]" in text
            result["negative"].append({"case": label, "status": "passed" if rejected else "failed", "log": log})
        passed = all(row["status"] == "passed" for row in result["matrix"] + result["negative"])
        result["status"] = "passed" if passed else "failed"
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        result["status"] = "failed"
        result["error"] = str(error)
    finally:
        (run / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{result['status']}: {run / 'result.json'}")
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
