# Livt.IO Hardware Notes

## RAM

`Ram` wraps `InternalRam`, an `@Opaque` Livt component backed by the handwritten
`InternalRam.vhd` primitive. The public wrapper owns range checking and write
enable sequencing; the VHDL primitive owns storage. The VHDL source lives next to
the opaque Livt declaration at `src/memory/InternalRam.vhd`.

The published RAM shape is fixed:

- 2048 addressable cells
- 11-bit internal address
- 8-bit data

`ReadByte(address)` returns `0x00` for invalid addresses. `WriteByte(address,
value)` ignores invalid addresses.

## UART

UART framing defaults to 8-N-1 and is specialized through component value
parameters:

- one low start bit
- `UartDataBits.Five`, `Six`, `Seven`, or `Eight`, least significant bit first
- `UartParity.None`, `Even`, or `Odd`
- `UartStopBits.One` or `Two`, each idle-high

Narrow frames consume and produce a byte at the API boundary. TX ignores unused
most-significant bits; RX zero-fills them. Format branches are evaluated
statically, so an 8-N-1 instance has no runtime format selector or configurable
divider.

RX and TX derive their timing from `this.context.TicksPer(BAUD)`, with a default
baud of `115200Hz`. `BAUD` is a component value parameter forwarded through each
wrapper, so it can determine counter widths without becoming runtime hardware.
The intrinsic rounds to the nearest whole clock tick (ties upward, minimum one
tick); achieved baud is `clock frequency / ticks per bit`.

The validated matrix covers 12, 25, 50, 100, and 125 MHz at 9600, 115200,
921600, and 1 Mbaud. Use at least 12 ticks per bit for the currently documented
operating envelope, and check rounding error and the peer's clock tolerance.
This is not a guarantee for arbitrary clock/baud combinations or line disturbances.
Baud arguments must be positive integral static values and are checked by the compiler;
an inadequate clock-to-baud ratio is not currently rejected automatically.

Do not pass a calculated runtime tick count or modify RX/TX constants. See the
[timing verification contract](../verification/uart-timing/README.md) for measured
latencies, low-ratio characterization, and synthesis costs.

## FIFO Behavior

TX is idle-high during reset. The transmitter stores the inverted line state
(reset value zero) and drives its physical output combinationally. Reset aborts
an in-flight frame and discards FIFO work; a peer may observe a truncated frame
when reset interrupts traffic. Clear is different: it discards queued data but
preserves a frame or launch byte already committed to transmission.

`BufferedUart` owns two `Livt.Collections.Fifo<byte, CAPACITY>`
instances. Each FIFO has one state owner. At each transfer edge:

- Reset wins over clear, and clear wins over push/pop.
- Pop requires an old item. Push requires space or a simultaneous accepted pop.
- Empty simultaneous push/pop accepts only push; there is no empty bypass.
- Full simultaneous push/pop accepts both and returns the old head.
- Rejected operations do not change occupancy or pointers.
- Clear resets occupancy/pointers without erasing payload cells.

This is an intentional library layering choice. Fifo provides hardware-level
signal access for the UART datapath. Collections Queue wraps the same core in
convenient application-level scheduled transactions, with extra arbitration
and completion latency. The UART does not route incoming or outgoing frame data
through Queue methods; it exposes its own scheduled application API above its
signal-level FIFOs. Both layers are synthesizable hardware, not a software/runtime
queue implementation.

`TryTransmit` and `TryReceive` wait for their FIFO result. Per-method dispatch
serializes callers; pending clear has priority over a pending API transfer.
A clear leaves a pending API request to be attempted afterward. Do not interpret
clear as cancellation of other callers. Error clear wins over coincident events.
A valid received frame rejected by a full FIFO increments the overflow counter.

TX pop captures the head into a launch register, pulses data-valid, and marks
launch pending until the transmitter becomes active. Clear and CTS must not
discard that committed byte. Queue emptiness alone therefore does not imply
transmit idleness. RX removal returns zero on failure, separately from acceptance.

RTS/CTS uses two clocked synchronization stages. RTS stop/resume levels reserve
`ceil(RX_CAPACITY / 8)` slots and use a reserve-sized hysteresis band.
At the default capacity 64 they are 56/48; capacity three uses 2/1.
This is headroom, not a guarantee for arbitrary peer reaction latency or CDC.
FIFOs are single-clock and do not provide asynchronous clock-domain crossing.

Scheduled API latency includes wrapper dispatch, arbitration, request/result
synchronization and return. It varies with contention; no one-cycle method claim
is made. FIFO edge acceptance and API completion are distinct events.

FIFO addresses and occupancy use capacity-derived widths, and payload arrays
use `@UninitializedStorage` so reset does not erase their cells. Physical RAM
inference and resource/timing comparisons remain target-dependent; the shared
source alone does not establish lower physical cost than the archived baseline.

RX/TX bit indices use three-bit vectors; the shared-UART verification harness
checks that exact width in generated VHDL. Unsigned conversions are used for
indexing and comparison. Baud counters use `Bits.RequiredFor(TICKS_PER_BIT - 1)`;
FIFO pointers/counts likewise use capacity-derived widths. These declarations are a source/generated-HDL
contract, not evidence of reduced device resources without synthesis comparison.

## Synthesis Notes

`LoopbackUart` is a serial loopback component that connects TX back to RX
internally. It is useful for simulation and self-test patterns; external serial
I/O should normally use `BufferedUart` or `RtsCtsBufferedUart`. Use the low-level
`Uart`, `UartReceiver`, and `UartTransmitter` components for custom unbuffered
designs. `LoopbackUart`, `BufferedUart`, and `RtsCtsBufferedUart` implement the
common `IBufferedUart` scheduled-operation contract.

## I2C

Usage examples and known limitations are collected in [`i2c.md`](i2c.md).

`Livt.IO` models I2C as open drain:

- `0` is driven by actively pulling a line low.
- `1` is represented by releasing the line and observing the external pull-up.
- `I2COpenDrainPins` maps `*_drive_low` requests to physical `inout` pins.
- Parent-owned plain `I2CBus` fields provide logical device endpoints.
- `I2CBusCombiner` merges one controller-side `I2CBus` attachment and one
  target-side `I2CBus` attachment before they reach the physical adapter.

`I2CBus` is still a scalar attachment contract. Use `I2CBusCombiner` when both
`I2CMaster` and `I2CSlave` are present in one simulation or design. Additional
targets will need either cascaded combiners or a future wider resolved-line abstraction.

`I2CMaster` is fixed to standard-mode timing in this release:

- source clock: 100 MHz
- I2C rate: 100 kHz
- half-period: 500 clock ticks

The master releases SCL for high phases and counts high-phase time only while
the observed SCL line is high, which gives basic clock-stretch tolerance. This
release is intentionally single-master, 7-bit-address, and byte-oriented. It does not
include arbitration, 10-bit addressing, multi-master recovery, or generic timing.

`I2CSlave` is a byte-event target. It matches one 7-bit address, exposes
received bytes through `HasReceivedByte()` / `GetReceivedByte()`, and transmits
the byte last written with `SetTransmitByte(value)`. It also exposes persistent
address, stop, and transmitted-byte events so higher-level target components can
react to repeated starts, read/write direction, and master ACK/NACK after reads.

`I2CRegisterSlave` adds a 256-byte register map on top of `I2CSlave`. The first
write byte selects the register pointer, subsequent write bytes store values and
auto-increment the pointer, and read-address requests prepare the current
register value for transmission. ACKed transmitted bytes advance the pointer and
prepare the next register value for repeated multi-byte reads; NACK leaves the
pointer at the last transmitted register.

## SPI

`SPIMaster` is a push-pull, single-controller implementation with these fixed
wire-level properties:

- SPI Mode 0 (`CPOL = 0`, `CPHA = 0`)
- most-significant bit first
- one MOSI data lane and one MISO data lane
- one active-low chip select
- 50 ns requested half-period, giving at most 10 MHz SCLK

The half-period tick count is obtained from the component context during
construction. At 100 MHz it is five ticks; at 50 MHz it rounds up to three
ticks. Keep the master in the context it inherits during construction so the
stored divider and sequential process use the same clock metadata.

Startup and reset leave the master idle with SCLK low, MOSI low, chip select
high, no command result pending, and a zero received byte. Selection waits at
least one half-period before a transfer can start. Deselection preserves at
least one half-period of hold time after the final SCLK edge.

Chip select remains asserted between completed byte transfers. This supports
flash protocols that send a command and address before streaming data. Modes 1
through 3, LSB-first transfers, multiple chip selects, dual SPI, quad SPI, and
SPI target behavior are outside the current contract.

Configuration-flash access may require vendor-specific routing. In particular,
an AMD 7-series board can require `STARTUPE2` to route user logic to the shared
configuration clock. Keep that primitive and board constraints outside
`Livt.IO`; adapt its signals to the portable `SPIBus` contract.

Configurable RAM depth, I2C timing, and additional SPI modes remain future
package additions. UART baud, data width, parity, and stop bits are compile-time
configuration.
