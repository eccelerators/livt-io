#!/usr/bin/env python3
"""Compile the actual library cores and verify hints and native edge contracts."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def reset_variants(code):
    """Count writers in each mutually exclusive elaboration alternative."""
    branch = re.compile(r"^([ \t]*)(\w+)_reset_(sync|async) : if [^\n]+ generate\n"
                        r"(.*?)^\1end generate;\n?", re.M | re.S)
    return [branch.sub(lambda match: match[4] if match[3] == mode else "", code)
            for mode in ("sync", "async")]


def has_single_writer(code):
    return all(len(re.findall(r"this_storage\(.*?<=", variant)) == 1
               for variant in reset_variants(code))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true")
    parser.add_argument("--no-optimizations", action="store_true")
    parser.add_argument("--reset-style", choices=("sync", "async"), default="sync")
    args = parser.parse_args()
    stage = Path(tempfile.mkdtemp(prefix="livt-io-memory-edges-"))
    print(f"Sources and evidence: {stage}", flush=True)
    sources = stage / "src"
    sources.mkdir()
    for source in (ROOT / "src/memory").glob("*.lvt"):
        shutil.copy2(source, sources)
    shutil.copy2(HERE / "MemoryPorts.lvt", sources)
    shutil.copytree(ROOT / "tests/memory", stage / "tests")
    components = sorted(p.stem for p in (ROOT / "tests/memory").glob("*Test.lvt"))
    (stage / "livt.toml").write_text(
        '[project]\nname="MemoryPorts"\npath="src"\noutdir="out"\n'
        '[tests]\npath="tests"\ncomponents=[' + ','.join('"' + n + '"' for n in components) + ']\n'
        '[vhdl]\nfile_header=false\n')
    environment = dict(os.environ)
    environment.pop("_JAVA_OPTIONS", None)
    command = [environment.get("LIVT", "livt"), "test", "-f", f"--default-reset-style={args.reset_style}"]
    if args.release:
        command.append("-R")
    if args.no_optimizations:
        command.extend(["-O", "none"])
    with (stage / "build.log").open("w") as log:
        subprocess.run(command, cwd=stage, env=environment, stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=120)
    generated = stage / "out"
    # Inspect every portable specialization, not merely the native bench pair.
    styles = set()
    for path in generated.rglob("*.vhd"):
        code = path.read_text()
        if "signal this_storage : t_this_storage_memory" not in code:
            continue
        if re.search(r"this_storage\s*<=", code):
            raise RuntimeError(f"Whole-array write/reset in {path}")
        if not has_single_writer(code):
            raise RuntimeError(f"Expected exactly one indexed write site in {path}")
        style = re.search(r'attribute ram_style of this_storage : signal is "(\w+)"', code)
        styles.add(style.group(1) if style else "auto")
    if styles != {"auto", "block", "distributed"}:
        raise RuntimeError(f"Missing compile-time style coverage: {styles}")
    for name, depth, width in (("8x64", 64, 8), ("32x16", 16, 32), ("32x32", 32, 32)):
        path = next(generated.rglob(f"Livt.IO.AsynchronousDistributedRam{name}.vhd"))
        code = path.read_text()
        shape = f"type t_this_storage_memory is array (0 to {depth - 1}) of std_logic_vector({width - 1} downto 0)"
        if shape not in code or 'attribute ram_style of this_storage : signal is "distributed"' not in code:
            raise RuntimeError(f"Inherited storage geometry or hint lost in {path}")
        if re.search(r"entity work\.|this_storage\s*<=|this_\w+_storage\s*<=", code):
            raise RuntimeError(f"Unexpected forwarding instance or whole-array write in {path}")
        if not has_single_writer(code):
            raise RuntimeError(f"Inherited memory does not have exactly one indexed writer: {path}")
    entities = {}
    for kind, style in (("SynchronousRam", "block"), ("AsynchronousRam", "distributed")):
        matches = [p for p in generated.rglob(f"Livt.IO.{kind}_g_*.vhd")
                   if not p.name.endswith(".Package.vhd") and re.search(
                       r"type t_this_storage_memory is array \(0 to 2\) of std_logic_vector\(15 downto 0\)",
                       p.read_text()) and f'is "{style}"' in p.read_text()]
        if len(matches) != 1:
            raise RuntimeError(f"Expected exactly one {kind} entity: {matches}")
        code = matches[0].read_text()
        entities[kind] = re.search(r"^entity (\w+) is", code, re.M).group(1)
        if not re.search(r'attribute ram_style of this_storage : signal is "' + style + '"', code):
            raise RuntimeError(f"Missing {style} hint: {matches[0]}")
        if not re.search(r"type t_this_storage_memory is array \(0 to 2\) of std_logic_vector\(15 downto 0\)", code):
            raise RuntimeError(f"Unexpected storage geometry: {matches[0]}")
        if re.search(r"this_storage\s*<=", code):
            raise RuntimeError(f"Whole-array write/reset in {matches[0]}")
        if not has_single_writer(code):
            raise RuntimeError(f"Expected one indexed write site in {matches[0]}")
    bench = (HERE / "edges.vhd").read_text()
    bench = bench.replace("@SYNC@", entities["SynchronousRam"]).replace("@ASYNC@", entities["AsynchronousRam"])
    (stage / "edges.vhd").write_text(bench)
    ghdl = environment.get("GHDL", "ghdl")
    subprocess.run([ghdl, "-i", "--std=08", *map(str, generated.rglob("*.vhd")), str(stage / "edges.vhd")],
                   cwd=stage, check=True, timeout=60)
    subprocess.run([ghdl, "-m", "--std=08", "ram_edges"], cwd=stage, check=True, timeout=60)
    result = subprocess.run([ghdl, "-r", "--std=08", "ram_edges", "--stop-time=1us"],
                            cwd=stage, capture_output=True, text=True, timeout=30)
    (stage / "edges.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"Native simulation failed: {stage / 'edges.log'}")
    if "Simulation finished: RAM edge contracts verified" not in result.stdout:
        raise RuntimeError(f"Missing completion marker: {stage / 'edges.log'}")
    print(result.stdout.strip())
    root_code = next(generated.rglob("Livt.IO.Verification.MemoryPorts.vhd")).read_text()
    ram = re.search(r"scheduled_instance: entity work\.(\w+)", root_code).group(1)
    ram_code = next(p for p in generated.rglob("*.vhd")
                    if p.name.lower() == ram.replace("livt_io_", "livt.io.", 1) + ".vhd").read_text()
    interface = re.search(r"read_in : in t_(\w+)_read_in", ram_code).group(1)
    scheduled = (HERE / "scheduled.vhd").read_text().replace("@RAM@", ram).replace("@RAMTYPE@", interface)
    (stage / "scheduled.vhd").write_text(scheduled)
    subprocess.run([ghdl, "-i", "--std=08", str(stage / "scheduled.vhd")], cwd=stage, check=True, timeout=60)
    subprocess.run([ghdl, "-m", "--std=08", "ram_scheduled"], cwd=stage, check=True, timeout=60)
    result = subprocess.run([ghdl, "-r", "--std=08", "ram_scheduled", "--assert-level=error"],
                            cwd=stage, capture_output=True, text=True, timeout=30)
    (stage / "scheduled.log").write_text(result.stdout + result.stderr)
    if result.returncode or "Simulation finished: scheduled RAM" not in result.stdout:
        raise RuntimeError(f"Scheduled simulation failed: {stage / 'scheduled.log'}")
    print(result.stdout.strip())
    print(f"All RAM styles and edge contracts passed; evidence: {stage}")


if __name__ == "__main__":
    main()
