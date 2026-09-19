# RAM contracts and verification

Production RAMs are implemented in Livt. The VHDL files here are native
testbenches, not storage implementations. A test-only custom HDL backend under
`tests/memory` verifies substitution through the same `RamAccess` adapter.

| Contract | SynchronousRam | AsynchronousRam |
|---|---|---|
| Read | One enabled rising edge to response | Combinational address-to-data |
| Write | One enabled rising edge; holds read response | One non-reset rising edge with writeEnable |
| Throughput | One read **or** write per clock | One write per clock, continuously readable |
| Invalid address | Ignore command, hold response | Ignore write, return zero |
| Reset | Suppress commands, clear response, retain cells | Suppress writes, retain cells and combinational reads |
| Unwritten cells | Unspecified | Unspecified |

The array carries `@Memory(Style=STYLE)` and `@UninitializedStorage`.
Auto adds no attribute; Block and Distributed add direct synthesis hints.
Style is compile-time configuration, independent of access/reset behavior.

## Reproduce

With `livt` and GHDL on PATH:

```sh
livt test
python3 verification/memory/check.py
python3 verification/memory/check.py --no-optimizations
python3 verification/memory/check.py --release
python3 verification/memory/check.py --release --no-optimizations
python3 verification/memory/configurations.py
```

The checker stages all actual memory sources and their 22 functional tests,
checks all three style choices and direct indexed writes, then runs native
edge and scheduled-transaction assertions. Sources, generated files and logs
remain in the printed temporary directory. Fixed asynchronous specializations
are also checked for direct payload ownership with no child forwarding instance. LIVT and GHDL select executables.

The configuration checker rejects zero capacity and incompatible backend payload,
address type and capacity identity. Zero capacity currently diagnoses the invalid
derived width (`bits-required-for-invalid`); mismatches report
`invalidGenericBound`. Low-level ADDRESS width sufficiency is the caller's
responsibility, not an enforced library constraint.

## Verified results (2026-09-19)

- Complete Livt.IO: **139 passed, zero failures/skips**; resume baseline: 135.
- Memory-only: **22 passed** in debug/release, default optimizations and `-O none`.
- Native ports/inherited specializations: **106 ns** completion at 100 MHz, all four modes.
- Native scheduled RAM: **3206 ns**, all four modes.
- Four invalid-configuration cases rejected with expected diagnostics.
- Workspace RAM integration: one passing test; Eccelerators.Cli: **36 passed**.
- Migrated ML attention: **2 passed**; byte tensor banks: **3 passed**.
- Isolated Tiny Stories tokenizer/BPE memory consumers: **2 passed**.
- Workspace runner unit tests: nine passed.

Native port coverage includes first-edge writes, consecutive reads/writes,
exclusion, synchronous output hold, asynchronous reads between edges, invalid
addresses, reset suppression/retention and unchanged inherited-specialization edge timing.
Scheduled coverage includes simultaneous requests in both arbitration orders,
invalid accesses, reset cancellation of reads/writes, one- and three-edge reset,
post-reset restart and retained cells. No assertion depends on unwritten data.

### Scheduled latency

Measured at the generated `Ram<byte, 3, Block>` entity interface, from the
rising edge sampling a one-cycle `run` request to the edge where `busy` falls
after having asserted. These are **uncontended** latencies, asserted exactly in
`scheduled.vhd`, identical in all four tested generation modes:

| Transaction | Clock cycles |
|---|---:|
| Valid write | 19 |
| Valid read | 21 |
| Invalid write | 15 |
| Invalid read | 16 |

These numbers include Ram/IRam/RamAccess method dispatch, not merely storage
latency; a Livt caller adds its own dispatch/observation overhead. Busy does not
assert on the first request edge. Contention adds cycles. RamAccess reserves
two storage edges for a read (issue/capture), one for a write; use the low-level
core for one-command-per-clock datapaths. No Fmax claim follows from simulating
with a 100 MHz clock.

Every generated portable payload signal has one indexed write site, no
whole-array assignment and no payload reset. Compiler scratch declarations may
still appear; these are not area measurements. No synthesis allocation,
LUT/FF reduction or timing-closure claim is made.

Verification used Livt.IO baseline `214ebbc` plus these changes, livt-lang
`d905184`, generator `273b7853` plus the inherited-memory fix (#477), and
GHDL 6.0.0 (`e589c698c`). Generator SHA-256:
`db910b01a871f67400d6cd67e68ce0c7a2f0af64adcdf4a4384f69ccb67ffef6`.

## Consumer integration

The `livt` repository owns cross-package tests and workspace staging.
`make test-workspace-memory` tests the current library sources; optional
`--cli-root` and `--app-root` arguments include CLI and UART consumers without
editing release pins. See its README for the invocation.

The UART application currently fails GHDL analysis on undeclared scheduled
return-value variables in generated `Eccelerators.Cli.Cli.vhd`, with default
optimizations and `-O none` (compiler #476). The CLI package's own suite passes.
Do not treat that application gate or board smoke testing as completed.
No board was reprogrammed in this migration.

ML and Tiny Stories consumer checks used coherent local snapshots; focused
tokenizer coverage excludes the full Tiny Stories application, which still uses
an obsolete UART API. Consumer evidence is under
`/tmp/livt-memory-inheritance-consumers-81zgu8au` (staged sources and per-test logs).
These checks do not establish full application or board compatibility.

If a previously compiled opaque entity leaves GHDL referring to architecture
`rtl`, rebuild the GHDL work-library cache. Do not remove dependency state or
change tests to accommodate a stale cache.
