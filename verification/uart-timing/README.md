# UART timing contract

UART configuration is static: each component has a final
`BAUD: Frequency = 115200Hz` value parameter. RX and TX use the same forwarded
baud and effective context. The wire format remains 8-N-1 and FIFO capacity and
flow-control behavior are unchanged for this timing matrix. Other formats are
selected independently through compile-time enum-valued component parameters.

## Validated clock and baud combinations

Entries are clock ticks per bit. All combinations below pass independent TX bit
monitoring and RX stimulus at the requested baud, including back-to-back frames.

| Context | 9600 | 115200 | 921600 | 1 Mbaud |
|---|---:|---:|---:|---:|
| 12 MHz | 1250 | 104 | 13 | 12 |
| 25 MHz | 2604 | 217 | 27 | 25 |
| 50 MHz | 5208 | 434 | 54 | 50 |
| 100 MHz | 10417 | 868 | 109 | 100 |
| 125 MHz | 13021 | 1085 | 136 | 125 |

Ticks are rounded to the nearest integer, with half ticks rounded upward.
Achieved baud is `clockHz / ticks`; error is
`100 * (achievedBaud / requestedBaud - 1)` percent. The matrix's largest absolute
rounding error is approximately 0.4694% (25/50 MHz at 921600 baud).
Clock-source error and the remote endpoint's error must also be considered.

Use at least **12 ticks per bit** for this documented operating envelope. A
separate 1 Mbaud boundary sweep explores 1–12 ticks and four receive phases; its
results characterize this receiver rather than promising general operation below
the matrix. Ratios 5–12 pass all four sampled phases; ratios 1, 2, and 4 fail
all four, while ratio 3 passes only one. Low ratios can lose back-to-back frames.
The receiver stress matrix below measures selected digital disturbances and baud
mismatch. Metastability and physical board operation are not established by these
simulations.

The compiler rejects non-positive/non-integral baud operands and runtime values
for component value parameters. It does not currently reject inadequate context/baud
ratios: context timing does not always have a numeric value available to language
`static assert` evaluation. This is an explicit configuration-checking limitation,
not a runtime check or a claim that one tick per bit is supported by this UART.

## Latency and throughput

The 2026-09-16 run after correcting the transmitter's reset idle level measures
868 clocks per bit and 8680 clocks per ten-bit frame at 100 MHz/115200 baud.
It measures one clock from request assertion to the start edge and 8684 clocks
between frame starts with the test's wait-for-idle request policy (four gap
clocks). Bit/frame lengths are unchanged; the request/start boundary is not the
same as the older retained 2026-09-13 result (three request clocks, five gap clocks).
The current TX output is a combinational inversion of reset-low internal state,
so the physical wire is idle-high during reset without another publication stage.

The matrix records each configuration separately. Scheduled wrapper/FIFO calls
have additional costs; these numbers are not buffered or RTS/CTS throughput claims.
Current local evidence: `.livt/uart-timing/matrix-8dhdpqov/result.json` (all 20
combinations and four invalid-configuration checks passed). Rerun the command
below to regenerate the source/tool hashes and logs; physical timing is unmeasured.

## Reproduce

The [retained result](results/2026-09-13/result.json) records the measured matrix,
boundary outcomes, source/harness hashes, and installed compiler/generator hashes.

From the package root, with Livt and GHDL installed:

```sh
python3 verification/uart-timing/matrix.py
livt test -r UartBaudConfigurationTest
```

The script copies current core sources into a unique `.livt/uart-timing/matrix-*`
directory, compiles them once, runs the clock matrix and boundary characterization,
and checks invalid baud diagnostics. It records source hashes, commands,
measurements, and individual logs in `result.json`. Each tool command is bounded
to 180 seconds; the VHDL testbench also has a simulation watchdog. Boundary
failures are recorded separately from the required matrix pass/fail result.

The matrix exercises the default rate of 115200 baud and the other rates with
explicit component value arguments forwarded through `Uart`. The Livt wrapper test
covers named-constant and folded timing-expression arguments at 25 MHz/1 Mbaud
through the concrete buffered implementations. The ordinary UART tests also
exercise omitted component values.
Existing receiver, transmitter, unbuffered, buffered, loopback, and RTS/CTS tests explicitly run
at 100 MHz with an independent 868-tick expected value.

## Receiver stress matrix

Run `python3 verification/uart-timing/receiver.py` from the package root.
The independent peer sends eight back-to-back bytes (`00 FF 55 AA 81 7E A3 5C`)
and a scoreboard checks every received byte, loss, duplication, and unexpected
framing errors. The test does not loop the DUT transmitter back into its receiver.

The [retained result](results/2026-09-14-receiver/README.md) passes all **144 cases**:

- 12 MHz and 100 MHz contexts at 1 Mbaud (12 and 100 clocks per nominal bit).
- Peer frequency errors of -2%, 0%, and +2%, combined with four quarter-clock
  phase offsets.
- Clean traffic; an isolated one-eighth-bit false-start pulse; a one-clock
  inverted pulse one eighth into every data bit; invalid-stop rejection followed
  by recovery; a 30-bit continuous-low break followed by recovery; and alternating
  data-bit lengths shortened/lengthened by one clock with no accumulated drift.

No additional receiver hardware is needed for these measured cases. This is not
a guarantee for arbitrary noise, center-sample glitches, other jitter spectra,
all possible phase offsets, or every clock/baud ratio. Break may produce repeated
framing-error indications; the test requires no valid byte during break and
correct subsequent frames, not a particular error count. Ratios below the stated
operating envelope still require a configuration diagnostic in the toolchain.

Each command has a 60-second wall-clock bound, and the bench has a 200-us
simulation watchdog. Results include source, harness, and compiler/generator
hashes, exact commands, and one log per case. A failing case makes the script
exit nonzero.

## Hardware cost

The Cmod A7-35T benchmark compares complete, observable core interfaces at 100 MHz
against the preceding fixed-baud implementation. Context metadata is bound to the
clock configuration; it is not a runtime frequency input. Const-baud variants are
selected by their actual bound child configuration, not the generic default text
retained in generated entities.

At 115200 baud, Vivado synthesis measured 446 LUTs/380 registers for the
unbuffered core (now named `Uart`)
(previously 438/379), 3616/4636 for `BufferedUart` (3698/4642), and 3695/4694 for
`RtsCtsBufferedUart` (3694/4685). All use no BRAM or DSP. These are mapped results,
not a promise of zero storage overhead or unchanged synthesis heuristics.
Setup slack at the declared 10 ns clock was +4.581, +4.269, and +4.273 ns
respectively. OOC estimated hold slack remains negative; this is not routed timing
closure, measured Fmax, or hardware sign-off. See the board repository's retained
reports for tool version, constraints, provenance, and detailed resource evidence.

At 100 MHz/1 Mbaud the unbuffered core uses 448 LUTs and 380 registers, with no
BRAM or DSP, and +4.573 ns setup slack under the same OOC constraint.
