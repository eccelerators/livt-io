# Livt.IO SPI

`Livt.IO` provides a portable byte-level SPI controller through two public
types:

- `SPIBus`: SCLK, MOSI, MISO, and active-low chip-select wiring;
- `SPIMaster`: an asynchronous Mode 0 controller for one attached device.

## Timing and context

The controller requests a 50 ns half-period and converts it with
`this.context.TicksFor(50ns)` during construction. The containing component
supplies the context automatically. Instantiate the master inside the desired
clock context so construction and the controller process use the same domain.

The conversion rounds positive durations up to at least one tick. Examples:

| Context clock | Half-period ticks | Resulting SCLK |
| --- | ---: | ---: |
| 100 MHz | 5 | 10 MHz |
| 50 MHz | 3 | approximately 8.33 MHz |

The rounded result does not exceed the requested 10 MHz bus frequency.

## Startup and reset

The controller starts idle with deterministic outputs and state:

- SCLK is low;
- MOSI is low;
- active-low chip select is high;
- `IsBusy()`, `IsSelected()`, and `HasResult()` return `false`;
- `GetReceivedByte()` returns `0x00` until the first transfer completes.

## Transaction flow

Commands are asynchronous and sticky completion is exposed through
`HasResult()`:

1. Call `BeginSelect()` and wait until `IsBusy()` is false.
2. Call `BeginTransfer(value)` for each command, address, or payload byte.
3. Read `GetReceivedByte()` after each completed transfer when needed.
4. Call `BeginDeselect()` and wait for completion.

`BeginSelect()` provides at least one SCLK half-period of chip-select setup time.
`BeginDeselect()` holds chip select active for at least one half-period after the
last SCLK edge. `HasResult()` remains set until `ClearResult()` or until another
accepted command starts.

Chip select stays low between byte transfers. This is required by common SPI
flash read transactions. Starting a command while another command is active,
transferring while deselected, selecting twice, or deselecting twice returns
`false` without changing controller state.

## Mode 0 behavior

SCLK is low while idle. MOSI is established during the low phase and MISO is
sampled during the following high phase. Bytes are shifted most-significant bit
first and transmission and reception happen simultaneously.

## Scope

Version 1.1.0 intentionally supports one portable baseline:

- Mode 0 only;
- one controller and one active-low chip select;
- one MOSI and one MISO lane;
- byte-level full-duplex transfers.

Device commands, address widths, flash erase/program sequencing, and row
buffers belong in device or application adapters. Vendor primitives and board
pin constraints belong in board-specific wrappers.
