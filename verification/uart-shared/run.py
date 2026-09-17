#!/usr/bin/env python3
"""Verify buffered UART implementations using the local Collections package."""
import json
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[2]


def main():
    collections = ROOT.parent / "livt-collections"
    version = tomllib.loads((collections / "livt.toml").read_text())["project"]["version"]
    run = Path(tempfile.mkdtemp(prefix="livt-uart-shared-"))
    shutil.copytree(ROOT / "src/uart", run / "src")
    (run / "tests").mkdir()
    components = ["BufferedUartPermissionTest", "UartBaudConfigurationTest", "UartFrameConfigurationTest",
                  "UartCapacityTest", "ConcurrentUartTest"]
    for component in components:
        shutil.copy2(ROOT / "tests/uart" / f"{component}.lvt", run / "tests")
    (run / "livt.toml").write_text(
        '[project]\nname = "SharedUartVerification"\npath = "src"\noutdir = "out"\n'
        f'[tests]\npath = "tests"\ncomponents = {json.dumps(components)}\n'
        f'[dependencies]\nLivt.Collections = {{ version = {json.dumps(version)}, '
        f'path = {json.dumps(str(collections))} }}\n')
    log_path = run / "simulation.log"
    with log_path.open("w") as log:
        result = subprocess.run(["livt", "test", "-f"], cwd=run, stdout=log,
                                stderr=subprocess.STDOUT, timeout=300)
    output = log_path.read_text()
    if result.returncode or "15 passed, 0 failed, 0 skipped" not in output or "Simulation finished" not in output:
        raise RuntimeError(f"Shared UART verification failed: {log_path}")
    for component in ("UartReceiver", "UartTransmitter"):
        entities = [path for path in (run / "out/debug/main").glob(f"Livt.IO.{component}*.vhd")
                    if re.search(r"^entity ", path.read_text(), re.M)]
        if not entities:
            raise RuntimeError(f"Missing generated {component}")
        for entity in entities:
            declarations = re.findall(r"variable bit_index\s*:\s*([^;]+);", entity.read_text())
            if len(declarations) != 1 or not re.fullmatch(
                    r'std_logic_vector\(2 downto 0\)\s*:=\s*"000"', declarations[0]):
                raise RuntimeError(f"Expected exactly one three-bit index: {entity}")
        parity_state = f"{component.removeprefix('Uart').lower()}_paritybit"
        parity_specialized = [parity_state in entity.read_text() for entity in entities]
        if not any(parity_specialized) or all(parity_specialized):
            raise RuntimeError(
                f"Expected both parity and compiler-elided no-parity {component} entities")
        second_stop_state = f"{component.removeprefix('Uart').lower()}_secondstopbit"
        stop_specialized = [second_stop_state in entity.read_text() for entity in entities]
        if not any(stop_specialized) or all(stop_specialized):
            raise RuntimeError(
                f"Expected both two-stop and compiler-elided one-stop {component} entities")
    print(f"Buffered UART implementations: fifteen tests passed; evidence: {run}")


if __name__ == "__main__":
    main()
