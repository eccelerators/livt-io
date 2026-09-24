# Shared buffered UART implementation

Run `python3 verification/uart-shared/run.py` from Livt.IO. It snapshots the UART
sources and test into a fresh temporary project and uses the sibling
`livt-collections` package as a local path dependency. Commands are bounded and
require both the test summary and `Simulation finished`. Logs and generated HDL
remain in the printed temporary directory.

Use `--reset-style=sync` (the default) or `--reset-style=async` to exercise the
compiler's project reset policy. Structural checks inspect each mutually
exclusive elaboration alternative separately; each selected UART still owns
one three-bit bit index.

The three tests use a 100 MHz context, 1 Mbaud, and RX/TX capacities of three.
They check full rejection, blocked-but-pending transmit status, ordered loopback,
empty receive, RX overflow and recovery, and TX clear during an active frame.
Permission is supplied synchronously; this does not verify a CTS synchronizer.

The public variants now use the shared `BufferedUart` implementation and satisfy
the `IBufferedUart` contract. The harness also includes baud/byte-forwarding tests
through the concrete implementations, two capacity-three RTS/CTS
tests for partial-send and clear behavior, a concurrent two-producer/consumer
UART test, and four compile-time frame-format tests. The format tests cover
5-N-2, 7-E-1, 8-O-2, byte truncation/zero extension, and independent parity-error
rejection. All fifteen methods must pass without skips. Commands have a five-minute
wall-clock bound; full-package coverage remains a separate `livt test` run.

The capacity test distinguishes a valid zero byte from failed receive, checks
blocked-but-pending status and RTS hysteresis, and verifies that clear removes
blocked queued data. The concurrency test checks each producer's ordering,
completion, final idleness, and absence of receive overflow.

Reset-edge integration and cycle-accurate contention are covered by the boundary
harness below. FPGA resource/timing comparisons remain separate; no area or Fmax
claim follows from these simulations.

## Boundary contract (2026-09-16)

```sh
python3 verification/uart-shared/boundaries.py
```

This builds the actual `BufferedUart` with capacity-three FIFOs and 1 Mbaud at 100 MHz,
then drives its generated method ports. An independent serial decoder checks
the wire as well as the buffered base's loopback receive path. It verifies 283 cases:

- 25 clear-versus-launch offsets: a committed first byte is preserved, while
  queued later bytes are discarded. In this generated implementation, permission
  offsets 0–2 launch one frame and offsets 3–24 launch none.
- 25 full-TX enqueue-versus-launch offsets: returned acceptance agrees with the
  observed ordered byte stream.
- 122 full-RX arrival-versus-clear/pop offsets: old bytes stay ordered, only
  accepted new bytes remain, and rejected arrivals agree with overflow counts.
- 100 resets across pending transmit, receive and TX/RX clear method phases.
- 11 resets during physical-frame phases, followed by successful fresh traffic.

TX must be idle-high during reset. The reset regression originally detected a
startup low pulse; the transmitter now stores inverted line state and drives
TX combinationally. Reset discards work and may truncate an active frame;
clear preserves an active or committed frame. This is an intentional distinction.

Uncontended direct base method costs were 16 edges for TryTransmit, 11 for
empty TryReceive and 9 for either clear. Counts include the first edge sampling
the run pulse through observed busy deassertion. These exclude caller-side
dispatch, contention and wrapper costs; they are not throughput guarantees.

Every call is bounded to 96 edges, the testbench to 12 ms, and each tool invocation
to 180 seconds. The printed directory retains exact sources, generated HDL,
the instantiated harness, logs and result.json with UART, Collections, installed
tool and generated-file hashes. Build logs may contain private Java launch options;
review them before sharing. The current evidence directory is printed by each run.

After the reset correction, all 123 IO tests pass and the 20-case independent
clock/baud matrix plus four invalid-configuration checks pass. The timing guide
records the changed request/start boundary separately from unchanged bit periods.

## Verified integration (2026-09-16)

- Full Livt.IO suite: `livt test -f`, 127 passed, zero failures/skips.
- Shared/public harness: fifteen passed, zero failures/skips.
- Collections suite: `livt test -f`, 41 passed, zero failures/skips.
- FIFO edge scoreboard: capacities 1, 3, and 64 passed.
- Independent UART timing matrix: all 20 clock/baud combinations passed.

These results describe the working tree measured on 2026-09-16. Rerun the repository commands
after checking out the reviewed code rather than relying on temporary local paths.
