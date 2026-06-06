# Livt.IO

`Livt.IO` provides reusable input/output components for the Livt base library.
It combines byte-addressable memory and UART serial I/O into one package so
applications can depend on `Livt.IO` instead of separate `Ram` or `Uart`
packages.

The 0.1.0 package surface is intentionally small and hardware-oriented:

- `Livt.IO.Ram`: 2048-byte RAM wrapper backed by an opaque VHDL primitive.
- `Livt.IO.UartReceiver`: 8-N-1 UART receive block.
- `Livt.IO.UartTransmitter`: 8-N-1 UART transmit block.
- `Livt.IO.UartBase`: low-level combined RX/TX UART block with explicit signals.
- `Livt.IO.BufferedUart`: UART controller with 64-byte TX/RX FIFOs.
- `Livt.IO.Uart`: application-friendly buffered UART wrapper.
- `Livt.IO.LoopbackUart`: serial loopback wrapper that connects TX to RX.

## 📦 Package

```toml
[dependencies]
Livt.IO = "0.1.0"
```

`Livt.IO` is part of the official Livt base library package set. New packages
should depend on `Livt.IO`; `Livt.IO` supersedes the standalone `Ram` and `Uart` packages for new code.

## 📚 Namespaces

`Livt.IO` keeps public components in the root `Livt.IO` namespace for short,
compatible call sites.

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

## 🧪 Build and Test

```sh
livt test
```

To force a clean regeneration without removing dependencies:

```sh
rm -rf out .livt/src.json .livt/ghdl
livt test
```

Short examples live in [`docs/usage.md`](docs/usage.md). Hardware and synthesis
notes live in [`docs/hardware-notes.md`](docs/hardware-notes.md).

## 🛠️ Development Notes

- Keep public components in `namespace Livt.IO`.
- Keep tests in `namespace Livt.IO.Tests`.
- Use `byte` for byte-oriented public APIs.
- Keep implementation notes and hardware caveats in `docs/hardware-notes.md`.
- Do not add `COMPILER.md` unless there is a reproducible compiler bug.

## 🚧 Outlook

Future additions may include configurable UART timing, configurable FIFO sizes,
word-level RAM helpers, dual-port RAM, and additional I/O protocol adapters.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
