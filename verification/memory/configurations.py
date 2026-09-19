#!/usr/bin/env python3
"""Exercise public RAM configuration diagnostics using isolated library snapshots."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    stage = Path(tempfile.mkdtemp(prefix="livt-io-memory-invalid-"))
    print(f"Configuration diagnostic evidence: {stage}", flush=True)
    environment = dict(os.environ)
    environment.pop("_JAVA_OPTIONS", None)
    cases = {
        "zero-capacity": ("Ram<byte, 0>", r"RAM capacity must be positive|bits-required-for-invalid"),
        "payload-mismatch": ("RamAccess<uint, logic[2], 3, SynchronousRam<byte, logic[2], 3>>", r"invalidGenericBound"),
        "address-mismatch": ("RamAccess<byte, logic[3], 3, SynchronousRam<byte, logic[2], 3>>", r"invalidGenericBound"),
        "geometry-mismatch": ("RamAccess<byte, logic[2], 4, SynchronousRam<byte, logic[2], 3>>", r"invalidGenericBound"),
    }
    for name, (declaration, diagnostic) in cases.items():
        project = stage / name
        sources = project / "src"
        sources.mkdir(parents=True)
        for source in (ROOT / "src/memory").glob("*.lvt"):
            shutil.copy2(source, sources)
        (sources / "Invalid.lvt").write_text(
            "using Livt.IO\ncomponent Invalid {\n bad: " + declaration + "\n}\n")
        (project / "livt.toml").write_text('[project]\nname="InvalidMemory"\npath="src"\noutdir="out"\n')
        result = subprocess.run([environment.get("LIVT", "livt"), "build", "-f"],
                                cwd=project, env=environment, capture_output=True,
                                text=True, timeout=120)
        output = result.stdout + result.stderr
        (project / "build.log").write_text(output)
        if result.returncode == 0 or not re.search(diagnostic, output, re.I):
            raise RuntimeError(f"Missing expected rejection for {name}: {project / 'build.log'}")
        print(f"Rejected {name} with the expected diagnostic.", flush=True)


if __name__ == "__main__":
    main()
