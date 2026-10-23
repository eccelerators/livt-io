# Changelog

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
- I2C tests and consumer documentation follow the Livt design guide's layout,
  ownership, clock/reset, acceptance and completion conventions.

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
