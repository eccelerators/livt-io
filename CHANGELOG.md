# Changelog

## 1.7.0

### Added

- `IReadOnlyBlockDevice`: transport-independent scheduled access to media geometry,
  one retained block read, completion polling, byte access, cancellation and release.
- `BlockReadState` distinguishes Idle, Active, Complete and Failed. Accepted reads
  reserve the slot until release; only successful completion exposes payload bytes.
- Public documentation for block ownership, backpressure, disconnect/reset behavior
  and provider-selected block sizes, storage and timing.

### Compatibility and dependencies

- Existing APIs remain unchanged. Continue to use `Livt.Collections 1.4.0`.
- The new contract introduces no USB or filesystem dependency and imposes no fixed
  block size, memory implementation or scheduled-call cycle count.

## 1.6.0

### Added

- `SequentialRam<T, CAPACITY = 64, STYLE = MemoryStyle.Block>`: compact scheduled
  storage implementing `IRam<T>`, with one command path and no internal arbitration.
  Each operation must complete before the next begins, including calls from
  different processes. The default backend requests block RAM.
- Regression coverage for read/write ordering, invalid addresses, non-power-of-two
  capacity and 64-bit payloads in a single-cell memory.

### Changed

- Document when to use sequential access, arbitrated `Ram` access or direct
  signal-level memory ports, with configurable storage backends.

### Compatibility and dependencies

- Existing public APIs remain unchanged.
- Cells survive reset and unwritten cells are unspecified. Reset cancels a pending
  operation and clears the read response. Invalid reads return zero; invalid writes
  leave memory unchanged.
- Continue to depend on `Livt.Collections 1.4.0`.

## 1.5.0

### Added

- `ISPITransactions` and `SPITransactions`: scheduled, exclusive Mode 0
  transactions over an owned `SPIMaster`, with context-derived timing.
- `ISPIFlash` and `SPIFlash`: JEDEC identification, buffered reads, page-fragment
  programming, aligned sector erase, write-enable checks and bounded readiness
  polling for single-lane SPI NOR with 24-bit addresses (up to 16 MiB).
- Consumer-selected flash staging storage through `MemoryStyle` and an optional
  `IRam<byte>` provider. Block-style RAM is the default; distributed RAM and
  custom storage implementations are supported.
- `ArrayRam<T, CAPACITY>`: scheduled, resettable logic-array storage implementing
  `IRam<T>`, for consumers that need zeroed payload on reset.
- Regression coverage for transaction timing across clock contexts, flash
  commands and failure paths, staging storage, and array-backed memory.

### Changed

- Split SPI bit advancement into an explicit state to retain transfer phase
  transitions. SPI transfer timing tests cover byte reception and clock edges.
- Document flash ownership, staging initialization, timeout behavior, storage
  selection and board integration requirements.

### Fixed

- Keep MII discard metadata stable until transmit acknowledgement. Late abort or
  link loss now affects only the MAC-domain completion result, avoiding an unsafe
  update across clock domains. Add late-abort/link-loss regression coverage and
  document bounded mailbox payload timing.

### Compatibility and dependencies

- Existing public APIs remain available. Depend on `Livt.Collections 1.4.0`.
- `SPITransactions` defaults to a 100 ns half-period and requires at least five
  context ticks per half-period; choose a longer duration for slower contexts or
  registered physical adapters. Do not assume a fixed byte-transfer cycle count.
- Flash capacity and geometry must match the device. The driver does not clear
  protection bits, perform chip erase, or manage application partitions.
  Program completion means the device is ready; read back to verify contents.
- Inferred RAM payload survives reset; `ArrayRam` resets its payload to zero.
  Flash staging initializes to zero on first use after reset with every backend.

## 1.4.0

### Added

- Full-duplex MII media adapter with independent PHY RX/TX clocks, block-memory
  asynchronous FIFOs, complete-frame TX commit, and 10/100 Mb/s operation.
- DP83848 PHY identification, MII selection, full-duplex negotiation, link/speed
  monitoring, bounded reset polling, and retry after MDIO errors.
- Livt tests for both media clock rates, repeated frames, abort/reuse, malformed
  receive events, overflow, and PHY recovery. Board qualification remains separate.

### Compatibility and dependencies

- Existing MAC, RMII, UART, I2C, SPI, and RAM APIs remain unchanged.
- Use `Livt.Collections 1.4.0` for the asynchronous FIFO implementation.
- MII requires a 50 MHz MAC context, separate PHY RX/TX contexts, coordinated
  asynchronous reset assertion, local reset release, and board CDC/I/O constraints.
- Full duplex only; no half-duplex collision handling or pause-frame flow control.

### Changed

- Keep MII fixtures and helpers as ordinary files under `tests/`, registered in
  the package test catalog; remove development-only verification projects.

## 1.3.0

### Added

- Consumer-selected I2C bus frequency through `I2CMaster<BUS_FREQUENCY,
  STRETCH_TIMEOUT>`, defaulting to `100000Hz` and `1ms`. Phase and timeout
  counts derive from the inherited clock context.
- Bounded clock stretching with `HasTimedOut()`. Timeout completes the command,
  releases both open-drain requests, clears ACK/data, and permits later commands.
- `HalfPeriodTicks()` for inspecting context-derived I2C phase timing.
- Livt tests for measured bus phases at 50 MHz and 100 MHz, configurable bus
  frequency and timeout, line release, and successful reuse after timeout.

### Changed

- Replaced stale links to absent verification reports with maintained tests and
  hardware guidance.

- I2C timing supports standard-mode frequencies from 1 Hz through 100 kHz;
  state transitions, input sampling and stretching can reduce the achieved rate.
- I2C timeout and NACK are distinct outcomes. ACK and NACK queries both return
  false after a timeout; callers must check `HasTimedOut()` before reading data.
- Documented I2C ownership, clock/reset, acceptance and completion conventions.

### Upgrading from 1.2.0

- Existing `new I2CMaster(bus)` calls retain the default 100 kHz target rate.
  Timing now adapts to the consumer clock instead of assuming 100 MHz.
- Clock stretching no longer waits indefinitely: the default limit is 1 ms per
  continuous released-SCL wait. Select a longer positive `STRETCH_TIMEOUT` for
  devices that need it. This is not a whole-transaction deadline.
- After `HasResult()`, check `HasTimedOut()` before ACK/NACK or byte results.
  A newly accepted command or `ClearResult()` clears the timeout status.
- The fixed public `CLOCK_HZ` and `I2C_HZ` constants have been removed. Use the
  consumer context and `BUS_FREQUENCY` configuration instead. Use the instance's
  `HalfPeriodTicks()` rather than assuming a fixed 500-tick phase.
- Timeout releases the controller's lines; it cannot release a target's stuck
  output and does not generate recovery pulses or guarantee a STOP condition.
- Fast-mode timing, multi-controller arbitration and 10-bit addresses remain
  unsupported.

## Earlier releases

This changelog starts with 1.3.0. Earlier release history remains in Git.
