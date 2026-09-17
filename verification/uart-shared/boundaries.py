#!/usr/bin/env python3
"""Verify production UART launch/clear and reset boundaries through its HDL ports."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[2]


def main():
    run = Path(tempfile.mkdtemp(prefix="livt-uart-boundaries-"))
    collections = ROOT.parent / "livt-collections"
    version = tomllib.loads((collections / "livt.toml").read_text())["project"]["version"]
    shutil.copytree(ROOT / "src/uart", run / "src")
    (run / "tests").mkdir()
    shutil.copy2(ROOT / "tests/uart/BufferedUartPermissionTest.lvt", run / "tests")
    (run / "livt.toml").write_text(
        '[project]\nname="UartBoundaryVerification"\npath="src"\noutdir="out"\n'
        '[tests]\npath="tests"\ncomponents=["BufferedUartPermissionTest"]\n'
        f'[dependencies]\nLivt.Collections={{version={json.dumps(version)},path={json.dumps(str(collections))}}}\n')
    def command(args, name):
        with (run / name).open("w") as log:
            result = subprocess.run(args, cwd=run, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=180)
        if result.returncode:
            raise RuntimeError(f"Command failed: {run / name}")

    command(["livt", "build", "-f"], "build.log")
    files = sorted((run / "out/debug").glob("*/*.vhd"))
    candidates = []
    for path in files:
        source = path.read_text()
        if (re.search(r"entity livt_io_buffereduart_\w+ is", source)
                and 'constant BAUD' in source
                and re.search(r"constant BAUD\s*:\s*real\s*:=\s*1000000(?:\.0)?;", source)
                and 'RX_CAPACITY : signed(31 downto 0) := signed\'(x"00000003")' in source):
            candidates.append((path, source))
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one capacity-three, 1 Mbaud buffered base: {len(candidates)}")
    path, source = candidates[0]
    entity = re.search(r"entity (\w+) is", source).group(1)
    port_block = source.split("\tport (", 1)[1].split("\n\t);", 1)[0]
    ports = re.findall(r"(\w+)\s*:\s*(in|out)\s+([^;\n]+)", port_block)
    declarations, maps = [], []
    wiring = {"ctor_rx": "wire", "ctor_tx": "wire", "ctor_launchpermission": "permission",
              "ctor_lvt_context_in": "context_value", "ctor_receivecount": "receive_count"}
    for name, direction, type_name in ports:
        if name in wiring:
            maps.append(f"{name} => {wiring[name]}")
            continue
        initial = ""
        if direction == "in":
            if name == "trytransmit_in":
                initial = ' := (data => x"00", run => \'0\')'
            elif name == "send_in":
                initial = " := (data => (others => (others => '0')), data_length => 0, run => '0')"
            else:
                initial = " := (run => '0')"
        declarations.append(f"signal {name}: {type_name}{initial};")
        maps.append(f"{name} => {name}")
    template = (ROOT / "verification/uart-shared/boundaries.vhd").read_text()
    harness = (template.replace("-- IMPORTS", "\n".join(re.findall(r"^use work\..*;", source, re.M)))
               .replace("-- DECLARATIONS", "\n".join(declarations))
               .replace("-- DUT", f"dut: entity work.{entity} port map (\n" + ",\n".join(maps) + ");"))
    harness_path = run / "boundaries.vhd"
    harness_path.write_text(harness)
    command(["ghdl", "-i", "--std=08", *map(str, files), str(harness_path)], "import.log")
    command(["ghdl", "-m", "--std=08", "uart_boundaries"], "elaborate.log")
    command(["ghdl", "-r", "--std=08", "uart_boundaries", "--assert-level=error"], "simulation.log")
    output = (run / "simulation.log").read_text()
    if "UART_BOUNDARIES_PASS" not in output:
        raise RuntimeError(f"Missing completion: {run / 'simulation.log'}")
    (run / "result.json").write_text(json.dumps({
        "configuration": {"clock_hz": 100000000, "baud": 1000000, "rx_capacity": 3, "tx_capacity": 3},
        "measurements": re.findall(r"MEASURE (\w+) cycles=(\d+)", output),
        "launch_clear": re.findall(r"LAUNCH_CLEAR offset=(\d+) frames=(\d+)", output),
        "rx_arrival": re.findall(r"RX_ARRIVAL operation=(\d+) offset=(\d+) remaining=(\d+)", output),
        "tx_launch": re.findall(r"TX_LAUNCH offset=(\d+) accepted=(true|false)", output),
        "source_sha256": {str(p.relative_to(run)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted((run / "src").rglob("*.lvt"))},
        "generated_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        "collections_sha256": {str(p.relative_to(collections)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sorted((collections / "src").rglob("*.lvt"))},
        "local_tool_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in (Path.home() / ".livt/livt.jar",
                                        Path.home() / ".livt/extensions/livt-gen-vhdl.jar") if p.is_file()},
        "harness_sha256": hashlib.sha256(harness_path.read_bytes()).hexdigest()
    }, indent=2) + "\n")
    print(f"UART boundary verification passed; evidence: {run}")


if __name__ == "__main__":
    main()
