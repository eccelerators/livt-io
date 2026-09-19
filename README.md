# Livt.IO

`Livt.IO` provides reusable input/output components for the Livt base library.
It combines byte- and word-addressable memory, UART serial I/O, and protocol bus
helpers into one package so applications can depend on `Livt.IO` instead of
separate `Ram` or `Uart` packages.

The 1.2.0 package surface is intentionally small and hardware-oriented:

- `Livt.IO.Ram<T, CAPACITY, STYLE>`: scheduled element-addressable memory implementing `IRam<T>`.
- `Livt.IO.BlockRam<T, CAPACITY>` / `DistributedRam<T, CAPACITY>`: inherited storage-style specializations.
- `Livt.IO.SynchronousRam<T, ADDRESS, CAPACITY, STYLE>`: one-edge read/write ports.
- `Livt.IO.AsynchronousRam<T, ADDRESS, CAPACITY, STYLE>`: combinational reads and clocked writes.
- `Livt.IO.AsynchronousDistributedRam<T, ADDRESS, CAPACITY>`: inherited distributed-style port core.
- `ISynchronousRam` / `IAsynchronousRam`: separate timing contracts; `RamAccess` accepts a custom synchronous provider.
- `Livt.IO.Ram16` / `Ram32`: 2048-element block-style specializations.
- `Livt.IO.AsynchronousDistributedRam32x16`, `AsynchronousDistributedRam32x32`, `AsynchronousDistributedRam8x64`: inherited asynchronous specializations.
- `Livt.IO.UartReceiver`: compile-time-configurable UART receive block.
- `Livt.IO.UartTransmitter`: compile-time-configurable UART transmit block.
- `Livt.IO.Uart`: low-level combined RX/TX UART block with explicit signals.
- `Livt.IO.IBufferedUart`: common scheduled contract for buffered UART implementations.
- `Livt.IO.BufferedUart`: FIFO-backed application UART with configurable TX/RX capacities.
- `Livt.IO.RtsCtsBufferedUart`: buffered UART with active-low RTS/CTS flow control.
- `Livt.IO.LoopbackUart`: serial loopback wrapper that connects TX to RX.
- `Livt.IO.I2CBus`: open-drain I2C bus contract.
- `Livt.IO.I2COpenDrainPins`: adapter from physical `inout` pins to `I2CBus`.
- `Livt.IO.I2CBusCombiner`: wired-AND combiner for one controller and one target.
- `Livt.IO.I2CMaster`: byte-level standard-mode I2C master.
- `Livt.IO.I2CSlave`: byte-event standard-mode I2C target.
- `Livt.IO.I2CRegisterSlave`: 256-byte register-file helper for I2C targets.
- `Livt.IO.SPIBus`: push-pull, single-data-lane SPI bus contract.
- `Livt.IO.SPIMaster`: context-timed, byte-level SPI Mode 0 controller.

## 📦 Package

```toml
[dependencies]
Livt.IO = "1.2.0-dev"
```

`Livt.IO` is part of the official Livt base library package set. New packages
should depend on `Livt.IO`; `Livt.IO` supersedes the standalone `Ram` and `Uart` packages for new code.

## 📚 Namespaces

`Livt.IO` keeps public components in the root namespace for short, compatible
call sites. Protocol components use readable prefixes such as `I2CMaster` and
`SPIMaster` rather than nested protocol namespaces.

| Component | Synthesizable | Purpose |
|---|---|---|
| `SynchronousRam<T, ADDRESS, CAPACITY, STYLE>` | Yes | One enabled read or write per clock; registered read response |
| `AsynchronousRam<T, ADDRESS, CAPACITY, STYLE>` | Yes | Combinational read and one clocked write port |
| `AsynchronousDistributedRam<T, ADDRESS, CAPACITY>` | Yes | Inherited combinational-read core with Distributed intent |
| `Ram<T, CAPACITY, STYLE>` | Yes | Scheduled Read/Write over one portable storage port |
| `BlockRam<T, CAPACITY>`, `DistributedRam<T, CAPACITY>` | Yes | Compile-time style specializations |
| `RamAccess<T, ADDRESS, ELEMENT_COUNT, STORAGE>` | Yes | Scheduled access over an injected synchronous provider |
| `Ram16` | Yes | Fixed 2048-word memory with 16-bit reads and writes |
| `Ram32` | Yes | Fixed 2048-word memory with 32-bit reads and writes |
| `AsynchronousDistributedRam32x16` | Yes | 16-word, 32-bit single-port distributed RAM |
| `AsynchronousDistributedRam32x32` | Yes | 32-word, 32-bit single-port distributed RAM |
| `AsynchronousDistributedRam8x64` | Yes | 64-byte single-port distributed RAM |
| `UartReceiver` | Yes | Serial RX with configurable data width, parity, and stop bits |
| `UartTransmitter` | Yes | Serial TX with configurable data width, parity, and stop bits |
| `Uart` | Yes | Combined RX/TX block with explicit handshake signals |
| `IBufferedUart` | Yes | Shared scheduled contract for buffered UART implementations |
| `BufferedUart` | Yes | FIFO-backed UART with configurable transmit and receive capacities |
| `RtsCtsBufferedUart` | Yes | Buffered UART with active-low RTS/CTS flow control |
| `LoopbackUart` | Yes | Buffered UART wrapper with internal TX-to-RX loopback |
| `I2CBus` | Yes | Open-drain I2C bus interface |
| `I2COpenDrainPins` | Yes | Physical `scl`/`sda` pin adapter |
| `I2CBusCombiner` | Yes | Combines controller and target drive-low requests |
| `I2CMaster` | Yes | Byte-level standard-mode I2C master |
| `I2CSlave` | Yes | Byte-event standard-mode I2C target |
| `I2CRegisterSlave` | Yes | 256-byte register-file helper built on `I2CSlave` |
| `SPIBus` | Yes | Push-pull, single-data-lane SPI bus interface |
| `SPIMaster` | Yes | Byte-level SPI Mode 0 master with context-derived timing |

## 🔌 API Overview

### Memory

`Ram<byte, 64>` is the ordinary scheduled API: `Read(address)`,
`Write(address, value)`, and `IsValidAddress(address)`, through `IRam<T>`.
Capacity counts elements and must be positive. Invalid reads return zero;
invalid writes do nothing. Default capacity is 64. `BlockRam<T>` defaults to
2048 elements; `DistributedRam<T>` defaults to 64. `Ram16` and `Ram32`
inherit 2048-element block-style RAM with 16-/32-bit logic-vector payloads.

All portable RAM implementations are now Livt source. Cells are unspecified
until written and survive reset. Reset cancels scheduled calls; it does not
erase memory. Applications needing zeros must explicitly write them first.

Storage uses `@Memory(Style=STYLE)` and `@UninitializedStorage`.
Auto emits no placement hint; Block and Distributed emit direct synthesis
attributes. These are requests, not guarantees of physical RAM allocation.
A style choice does not change read timing.

For one-command-per-clock datapaths, use `SynchronousRam` directly. For
combinational reads, use `AsynchronousRam`. Their separate interfaces include
the payload type, explicit unsigned address type, and `RamGeometry<CAPACITY>`
identity. The scheduled `Ram` derives its own narrow address width; low-level
users supply an address type large enough for every index.

The fixed `AsynchronousDistributedRam32x16`, `AsynchronousDistributedRam32x32`,
and `AsynchronousDistributedRam8x64` inherit `AsynchronousDistributedRam`,
which binds the Distributed hint on `AsynchronousRam`. They expose `address`,
boolean `writeEnable`, `writeData`, and `readData` directly; there is no
compatibility adapter. Wire ports in a combinational process when scheduled
code needs live observations.

`BlockRam` and `DistributedRam` remain scheduled APIs over synchronous storage.
“Asynchronous” in the new names identifies read timing; “Distributed” identifies
storage intent. Inheritance binds configuration without changing the access contract.

See [usage and migration](docs/memory.md) and
[contracts, measured latency, and verification](verification/memory/README.md).
The former nongeneric `Ram.ReadByte/WriteByte` API and opaque `InternalRam*`
primitives are removed; this is an explicit API/startup migration.

### UART

UART components derive bit timing from their component context. Every UART
component has a final `BAUD: Frequency = 115200Hz` value parameter, including
buffered, RTS/CTS, and loopback variants. Baud is structural configuration, so
it is part of the component type rather than a runtime constructor input:

```livt
new BufferedUart(rx, tx) // 115200 baud in the effective clock context
new BufferedUart<64, 64, UartDataBits.Eight, UartParity.None,
	UartStopBits.One, 921600Hz>(rx, tx)
```

Frame format is also selected at compile time. The defaults remain 8-N-1. Data
width accepts `UartDataBits.Five`, `Six`, `Seven`, or `Eight`; parity accepts
`UartParity.None`, `Even`, or `Odd`; and stop width accepts
`UartStopBits.One` or `Two`:

```livt
uart: BufferedUart<64, 64, UartDataBits.Seven, UartParity.Even, UartStopBits.Two>
```

Formats narrower than eight bits transmit only the least-significant selected
bits and zero-fill the unused most-significant bits on receive. Because these
are component value parameters, static specialization removes unselected frame
branches instead of adding runtime format selectors.

Named constants and forwarded const parameters are supported; runtime baud
changes are not. The validated clock/baud combinations, rounding error, sampling
limits, and reproducible measurements are documented in
[`verification/uart-timing/README.md`](verification/uart-timing/README.md).

`UartReceiver` pulses `rx_dv` for one cycle after a valid byte and pulses
`rx_frame_error` for one cycle after an invalid parity or stop bit. `UartTransmitter`
starts when `tx_dv` is pulsed, keeps `tx_active` high while a frame is in
flight, and pulses `tx_done` when transmission completes.

All buffered variants accept compile-time capacities, defaulting to 64 entries
each. `BufferedUart` owns the signal-level `Uart` plus two
`Livt.Collections.Fifo<byte, CAPACITY>` instances. `LoopbackUart` and
`RtsCtsBufferedUart` compose it and implement `IBufferedUart`, which gives the
compiler one common implementation contract. The wrappers delegate scheduled
methods with `IBufferedUart by buffered`. Applications can hold an `IBufferedUart`
reference when substitution is useful, or use a concrete component type directly.
`Uart` remains available for custom unbuffered compositions. The shared FIFO
dependency is declared in `livt.toml` as `Livt.Collections` version `1.1.0-dev`.

- `TryTransmit(data) bool` reports FIFO acceptance, not wire completion.
- `TryReceive(data: out byte) bool` atomically removes a byte. Failure assigns
  zero; a successful zero byte remains distinguishable from an empty queue.
- `IsTransmitting()` reports an active physical frame.
- `HasPendingTransmit()` includes pending API requests, queued bytes, committed launches, and active frames.
- `IsTransmitIdle()` means no transmit work remains.
- `GetReceiveCount()` and `GetTransmitSpace()` are snapshots, not reservations.
- `Send(data) int` accepts a prefix and returns its length. It stops at the first
  rejection; other producers may interleave. It is not an atomic message send.
- `ClearReceiveBuffer()` discards queued receive data.
- `ClearTransmitBuffer()` discards queued bytes, preserving an active frame or
  a byte already committed to launch.
- `GetFrameErrorCount()`, `GetReceiveOverflowCount()`, and `ClearErrors()`
  expose and clear receive errors.

These are scheduled methods, not one-clock operations. They form the
`IBufferedUart` contract, including `Send(byte[])`; compile-time interface
delegation preserves its inferred maximum capacity and per-call logical length.
Use `Uart` for cycle-sensitive or custom unbuffered applications. See
[hardware contracts](docs/hardware-notes.md#fifo-behavior).

RTS/CTS wrappers synchronize active-low `ctsN` before granting launch permission.
A committed or active frame finishes even if CTS changes. Active-low `rtsN`
uses capacity-derived hysteresis: reserve `ceil(RX_CAPACITY / 8)` entries,
stop at capacity minus that reserve, and resume one reserve below the stop level.
Defaults remain 56/48; receive capacity must be at least two for RTS/CTS.
Small buffers require a correspondingly prompt peer. Basic UART ties permission
active; elimination of unused flow-control logic still needs synthesis evidence.

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

### SPI

`SPIMaster` implements single-data-lane SPI Mode 0 with MSB-first, full-duplex
byte transfers. Chip select is controlled separately so a command, address,
and payload can remain in one transaction:

- `BeginSelect()` asserts the active-low chip select.
- `BeginTransfer(data)` exchanges one byte while chip select remains asserted.
- `BeginDeselect()` releases chip select after its hold interval.
- `IsBusy()`, `IsSelected()`, `HasResult()`, and `ClearResult()` expose state.
- `GetReceivedByte()` returns the byte sampled during the last transfer.
- `HalfPeriodTicks()` returns the context-derived SCLK half-period.

Accepted commands complete asynchronously. A `Begin*` call returns `false`
when its preconditions are not satisfied and leaves the controller unchanged.

The requested SCLK half-period is 50 ns. `SPIMaster` converts that duration with
`this.context.TicksFor(50ns)` during construction, so a parent-selected clock
context determines the divider. Positive durations round up to a complete
context tick; the resulting SCLK therefore never exceeds 10 MHz. MISO is
sampled on the Mode-0 rising edge; the flash may begin changing it on the
following falling edge.

At startup and reset, the controller is idle and deselected: SCLK and MOSI are
low, chip select is high, and `HasResult()` is false. The first received byte is
`0x00`.

## 🧪 Build and Test

```sh
livt test
```

To force a clean regeneration without removing dependencies:

```sh
livt clean
livt test
```

Short examples live in [`docs/usage.md`](docs/usage.md). Protocol details and
caveats live in [`docs/i2c.md`](docs/i2c.md) and [`docs/spi.md`](docs/spi.md).
Hardware and synthesis notes live in
[`docs/hardware-notes.md`](docs/hardware-notes.md).

## 🛠️ Development Notes

- Keep public components in `namespace Livt.IO`.
- Prefix protocol components with the protocol acronym, for example `I2CMaster`
  and `SPIMaster`.
- Keep tests in `namespace Livt.IO.Tests`.
- Use `byte` for byte-oriented public APIs.
- Keep implementation notes and hardware caveats in `docs/hardware-notes.md`.
- Do not add `COMPILER.md` unless there is a reproducible compiler bug.

## 🚧 Outlook

Future additions may include partial-word write APIs, dual-port RAM,
SPI modes 1 through 3, multiple chip
selects, quad-SPI transfers, and `SPISlave`.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
