# Livt.IO

`Livt.IO` provides reusable input/output components for the Livt base library.
It combines byte-addressable memory, UART serial I/O, and protocol bus helpers
into one package so applications can depend on `Livt.IO` instead of separate
`Ram` or `Uart` packages.

The 0.2.0 package surface is intentionally small and hardware-oriented:

- `Livt.IO.Ram`: 2048-byte RAM wrapper backed by an opaque VHDL primitive.
- `Livt.IO.UartReceiver`: 8-N-1 UART receive block.
- `Livt.IO.UartTransmitter`: 8-N-1 UART transmit block.
- `Livt.IO.UartBase`: low-level combined RX/TX UART block with explicit signals.
- `Livt.IO.BufferedUart`: UART controller with 64-byte TX/RX FIFOs.
- `Livt.IO.Uart`: application-friendly buffered UART wrapper.
- `Livt.IO.LoopbackUart`: serial loopback wrapper that connects TX to RX.
- `Livt.IO.I2CBus`: open-drain I2C bus contract.
- `Livt.IO.I2COpenDrainPins`: adapter from physical `inout` pins to `I2CBus`.
- `Livt.IO.I2CBusCombiner`: wired-AND combiner for one controller and one target.
- `Livt.IO.I2CMaster`: byte-level standard-mode I2C master.
- `Livt.IO.I2CSlave`: byte-event standard-mode I2C target.
- `Livt.IO.I2CRegisterSlave`: 256-byte register-file helper for I2C targets.

## 📦 Package

```toml
[dependencies]
Livt.IO = "0.2.0"
```

`Livt.IO` is part of the official Livt base library package set. New packages
should depend on `Livt.IO`; `Livt.IO` supersedes the standalone `Ram` and `Uart` packages for new code.

## 📚 Namespaces

`Livt.IO` keeps public components in the root namespace for short, compatible
call sites. Protocol components use readable prefixes such as `I2CMaster` and
future `SPIMaster` rather than nested protocol namespaces.

| Component | Synthesizable | Purpose |
|---|---|---|
| `Ram` | Yes | Fixed 2048-byte memory with byte reads and writes |
| `InternalRam` | Yes | Opaque VHDL-backed RAM primitive contract |
| `UartReceiver` | Yes | Serial RX for fixed 8-N-1 frames |
| `UartTransmitter` | Yes | Serial TX for fixed 8-N-1 frames |
| `UartBase` | Yes | Combined RX/TX block with explicit handshake signals |
| `BufferedUart` | Yes | UART with 64-byte transmit and receive FIFOs |
| `Uart` | Yes | Application-facing wrapper around `BufferedUart` |
| `LoopbackUart` | Yes | Buffered UART wrapper with internal TX-to-RX loopback |
| `I2CBus` | Yes | Open-drain I2C bus interface |
| `I2COpenDrainPins` | Yes | Physical `scl`/`sda` pin adapter |
| `I2CBusCombiner` | Yes | Combines controller and target drive-low requests |
| `I2CMaster` | Yes | Byte-level standard-mode I2C master |
| `I2CSlave` | Yes | Byte-event standard-mode I2C target |
| `I2CRegisterSlave` | Yes | 256-byte register-file helper built on `I2CSlave` |

## 🔌 API Overview

### Memory

`Ram` exposes a small byte-level random-access contract:

- `ADDRESS_WIDTH = 11`
- `CAPACITY = 2048`
- `MAX_ADDRESS = 2047`
- `IsValidAddress(address)`
- `WriteByte(address, value)`
- `ReadByte(address)`

Valid addresses are `0..2047`. Out-of-range reads return `0x00`; out-of-range
writes are ignored.

### UART

UART components use fixed 8-N-1 framing and `TICKS_PER_BIT = 868`, matching
115200 baud on a 100 MHz clock.

`UartReceiver` pulses `rx_dv` for one cycle after a valid byte and pulses
`rx_frame_error` for one cycle after an invalid stop bit. `UartTransmitter`
starts when `tx_dv` is pulsed, keeps `tx_active` high while a frame is in
flight, and pulses `tx_done` when transmission completes.

`BufferedUart` adds 64-byte TX and RX FIFOs:

- `Transmit(data)` returns `false` when the TX FIFO is full.
- `Receive()` returns `0x00` when the RX FIFO is empty.
- `GetAvailableBytes()` and `GetTransmitSpace()` expose FIFO state.
- `ClearReceiveBuffer()`, `ClearTransmitBuffer()`, and `ClearFrameErrors()`
  reset buffered state.

`Uart.Send(data)` is all-or-nothing: it queues the complete byte array only when
enough transmit space is available.

### I2C

I2C support is v1 byte-level and fixed to standard mode:

- `I2CMaster.CLOCK_HZ = 100000000`
- `I2CMaster.I2C_HZ = 100000`
- `I2CMaster.TICKS_PER_HALF_PERIOD = 500`

`I2CBus` models an open-drain bus attachment. The provider exposes observed
`scl` and `sda` levels, while devices request low drive through
`scl_drive_low` and `sda_drive_low`. `I2CBusCombiner` owns public
`controller` and `target` endpoints and wires them into one upstream adapter.

`I2CMaster` exposes asynchronous byte commands:

- `BeginStart()`, `BeginStop()`
- `BeginWriteByte(data)`
- `BeginWriteAddress(address)`, `BeginReadAddress(address)`
- `BeginReadByte(sendAck)`
- `IsBusy()`, `HasResult()`, `ClearResult()`
- `WasAckReceived()`, `WasNackReceived()`, `GetReadByte()`

Address helpers take unshifted 7-bit addresses in the range `0x00..0x7F` and
return `false` for invalid addresses.

`I2CSlave` exposes byte events:

- `HasReceivedByte()`, `GetReceivedByte()`, `ClearReceivedByte()`
- `SetTransmitByte(value)`
- `IsReadRequested()`, `ClearReadRequested()`
- `HasAddressMatch()`, `ClearAddressMatch()`
- `WasReadAddressed()`, `WasWriteAddressed()`
- `HasStopDetected()`, `ClearStopDetected()`
- `HasTransmittedByte()`, `WasTransmitAcked()`, `ClearTransmittedByte()`

`I2CRegisterSlave` wraps `I2CSlave` with a 256-byte register map. The first
write byte selects the register pointer; following write bytes store values and
auto-increment the pointer. Read requests load the current register value, and
ACKed transmitted bytes advance the pointer for repeated multi-byte reads.

- `SetRegister(address, value)`, `GetRegister(address)`
- `SetPointer(address)`, `GetPointer()`, `HasPointer()`, `ClearPointer()`
- `AcceptWriteByte(value)`, `PrepareReadByte()`, `GetCurrentRegister()`
- `HandleTransmittedByte(acked)`
- `HasWrittenRegister()`, `GetWrittenRegister()`, `GetWrittenValue()`,
  `ClearWrittenRegister()`

## 🧪 Build and Test

```sh
livt test
```

To force a clean regeneration without removing dependencies:

```sh
rm -rf out .livt/src.json .livt/ghdl
livt test
```

Short examples live in [`docs/usage.md`](docs/usage.md). I2C-specific examples
and caveats live in [`docs/i2c.md`](docs/i2c.md). Hardware and synthesis notes
live in [`docs/hardware-notes.md`](docs/hardware-notes.md).

## 🛠️ Development Notes

- Keep public components in `namespace Livt.IO`.
- Prefix protocol components with the protocol acronym, for example `I2CMaster`
  and future `SPIMaster`.
- Keep tests in `namespace Livt.IO.Tests`.
- Use `byte` for byte-oriented public APIs.
- Keep implementation notes and hardware caveats in `docs/hardware-notes.md`.
- Do not add `COMPILER.md` unless there is a reproducible compiler bug.

## 🚧 Outlook

Future additions may include configurable UART timing, configurable FIFO sizes,
word-level RAM helpers, dual-port RAM, and root-namespace SPI helpers such as
`SPIMaster` and `SPISlave`.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
