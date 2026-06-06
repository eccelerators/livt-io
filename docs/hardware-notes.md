# Livt.IO Hardware Notes

## RAM

`Ram` wraps `InternalRam`, an `@Opaque` Livt component backed by the handwritten
`InternalRam.vhd` primitive. The public wrapper owns range checking and write
enable sequencing; the VHDL primitive owns storage. The VHDL source lives next to
the opaque Livt declaration at `src/memory/InternalRam.vhd`.

The published 0.1.0 RAM shape is fixed:

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

No configurable RAM depth, UART baud, parity, or FIFO size is exposed in
`Livt.IO 0.1.0`. Those are expected future package additions.
