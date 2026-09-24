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
python3 verification/memory/check.py --release --reset-style=async
python3 verification/memory/configurations.py
```

The checker stages all actual memory sources and their 22 functional tests,
checks all three style choices and direct indexed writes, then runs native
edge and scheduled-transaction assertions. Sources, generated files and logs
remain in the printed temporary directory. Fixed asynchronous specializations
are also checked for direct payload ownership with no child forwarding instance. LIVT and GHDL select executables.

`--reset-style=sync|async` selects the compiler's reset policy (default: sync).
Writer-count assertions inspect each static reset alternative separately;
whole-array reset/write checks remain active for the complete generated HDL.
The selected policy changes registered control/response reset timing, not
payload retention or the distinction between synchronous and asynchronous reads.

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
still appear; these simulation checks are not area measurements. See the
separate vendor evidence below for the tested physical memory mappings;
no LUT/FF reduction or timing-closure claim follows from simulation.

Verification used Livt.IO baseline `214ebbc` plus these changes, livt-lang
`d905184`, generator `273b7853` plus the inherited-memory fix (#477), and
GHDL 6.0.0 (`e589c698c`). Generator SHA-256:
`db910b01a871f67400d6cd67e68ce0c7a2f0af64adcdf4a4384f69ccb67ffef6`.

## Consumer integration

The `livt` repository owns cross-package tests and workspace staging.
`make test-workspace-memory` tests the current library sources; optional
`--cli-root` and `--app-root` arguments include CLI and UART consumers without
editing release pins. See its README for the invocation.

Compiler #476 fixes the UART application's scheduled return lowering. Against
published Livt.IO `1.2.0-dev` and Collections `1.1.0-dev`, all 36 current CLI
tests pass with default optimizations and `-O none`; the complete UART session
passes in both modes at 24215585 ns. Checks stage current CLI/application
sources, not the older published CLI `1.1.0` implementation, without changing
checkout dependency pins. Evidence: `/tmp/livt-476-published.gyaFzW` and
`/tmp/livt-476-published-{cli,app}-{default,none}.log`.
No board was reprogrammed; vendor-project and board smoke checks remain separate.

## Vivado memory mapping (2026-09-19)

The synthesis-only workflow in `livt-cmod-a7-35t` stages fresh release sources
and uses published Livt.IO `1.2.0-dev`, Vivado 2026.1 and `xc7a35tcpg236-1`.
Run `make memory-synth` there for live-port probes; `make memory-verify` also
packages the staged current UART/CLI sources and synthesizes the board design.
It does not program hardware or generate a bitstream. Source/tool hashes,
commands, constraints and raw reports are kept in the vendor project, not the
compiler. See its `baselines/2026-09-19-issue-481/README.md` for the latch-free
result and `baselines/2026-09-19-issue-455/README.md` for the historical baseline.

Confirmed isolated mappings at 100 MHz synthesis constraints:

- `BlockRam<byte, 2048>`: one RAMB18E1.
- `DistributedRam<byte, 64>`: eight RAM64X1S (eight LUT memories).
- `AsynchronousDistributedRam8x64`: eight RAM64X1S.
- Direct synchronous cores with matching geometry/styles: the same memories.

Compiler #481 removes the two forwarding latches previously observed in each
scheduled RamAccess adapter. All five probes now pass the vendor latch guard;
their RAM mappings are unchanged. All 139 Livt.IO tests pass, with focused RAM
functional/native checks also passing in debug/release with default optimizations
and `-O none`. This does not establish timing closure or results for every
geometry/vendor. Board verification is recorded separately below.

The actual packaged UART application and complete Cmod board both synthesize.
Each CLI buffer (parser line and output) retains eight RAM64X1S cells in the
linked board netlist. The application instantiates no explicit BlockRam, so
block inference evidence comes from the isolated probe, not a board-total
assumption. With #481, all eight application/board forwarding latches are gone
(four RAM, four UART), as are their unclocked endpoints. Those synthesis-only
checks did not program a device or establish routed timing.
The new archived consumer manifest identifies
`work/memory-verification/consumers-ardgwuog` and the tested published packages;
isolated probes are from `cores-rqc74sx9`.

### Routed and physical closure (#455)

`livt-cmod-a7-35t/baselines/2026-09-19-issue-455-closure` records the completed
review and board test of that generated design. At 100 MHz, final routed setup/
hold slack is +0.675/+0.010 ns, with zero latches or unconstrained internal
endpoints and unchanged 16-cell CLI LUTRAM mapping. Board-specific constraints
mark the topology-checked UART synchronizer and specify configuration voltage;
DRC is clean and CDC reports only the recognized UART/reset chains. Existing
asynchronous external exceptions are reviewed, not broadened. An adjacent-slice
synchronizer placement advisory is retained with its +8.733 ns path margin.

All 113 byte-exact UART exchanges pass after JTAG loading and again after
authorized flash programming, verification and boot. The board is running the
new persistent image. Tests include RAM capacity boundaries, overflow recovery,
editing and 100 varying payloads. #455 is closed for this verified scope; this
does not claim other-vendor coverage, an MTBF measurement or exhaustive physical
RAM testing. No production library or dependency pin changed in this closure run.

## Other consumers

ML and Tiny Stories consumer checks used coherent local snapshots; focused
tokenizer coverage excludes the full Tiny Stories application, which still uses
an obsolete UART API. Consumer evidence is under
`/tmp/livt-memory-inheritance-consumers-81zgu8au` (staged sources and per-test logs).
These checks do not establish full application or board compatibility.

If a previously compiled opaque entity leaves GHDL referring to architecture
`rtl`, rebuild the GHDL work-library cache. Do not remove dependency state or
change tests to accommodate a stale cache.
