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

UART framing is fixed to 8-N-1:

- one low start bit
- eight data bits, least significant bit first
- one high stop bit
- no parity

`TICKS_PER_BIT = 868` corresponds to 115200 baud on a 100 MHz clock. To target a
different baud rate in this release, update the receiver and transmitter
constants together and rerun the full UART tests.

## FIFO Behavior

`BufferedUart` uses 64-byte transmit and receive FIFOs.

- `Transmit(data)` returns `false` when the transmit FIFO is full.
- Received bytes are dropped when the receive FIFO is full.
- `Receive()` returns `0x00` when the receive FIFO is empty.
- `ClearTransmitBuffer()` clears queued bytes but does not cancel a byte already
  in flight.
- Framing errors are counted until `ClearFrameErrors()` is called.

## Synthesis Notes

`LoopbackUart` is a serial loopback component that connects TX back to RX internally. It is useful for simulation and self-test patterns; external serial I/O should use `Uart`, `BufferedUart`, or the lower-level receiver/transmitter components.

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
SPI target behavior are outside the 1.1.0 contract.

Configuration-flash access may require vendor-specific routing. In particular,
an AMD 7-series board can require `STARTUPE2` to route user logic to the shared
configuration clock. Keep that primitive and board constraints outside
`Livt.IO`; adapt its signals to the portable `SPIBus` contract.

No configurable RAM depth, UART baud, parity, FIFO size, I2C timing, or SPI mode
is exposed in `Livt.IO 1.1.0`. Those are expected future package additions.
