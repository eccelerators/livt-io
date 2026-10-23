# Livt.IO I2C

`Livt.IO` provides byte-level I2C building blocks in the root `Livt.IO`
namespace:

- `I2CBus`: logical open-drain bus attachment.
- `I2COpenDrainPins`: adapter from physical `inout` pins to `I2CBus`.
- `I2CBusCombiner`: combines one controller attachment and one target attachment.
- `I2CMaster`: asynchronous byte-command I2C controller.
- `I2CSlave`: byte-event I2C target for one 7-bit address.
- `I2CRegisterSlave`: 256-byte register-file target built on `I2CSlave`.

I2C is modeled as open drain. Components do not drive `1`; they either request a
low level through `scl_drive_low` / `sda_drive_low` or release the line and
observe `scl` / `sda`.

## Consumer-selected timing

The master takes compile-time parameters `BUS_FREQUENCY: Frequency = 100000Hz`
and `STRETCH_TIMEOUT: Time = 1ms`. It derives phase and timeout counts from its
inherited clock context, just as UART derives bit timing from its baud rate.
The supported bus-frequency range is 1 Hz through 100 kHz (standard mode).

For example, a camera wrapper can forward both settings:

```livt
using Livt.IO

component CameraRegisterBus<BUS_FREQUENCY: Frequency = 100000Hz,
    STRETCH_TIMEOUT: Time = 1ms>
{
    master: I2CMaster<BUS_FREQUENCY, STRETCH_TIMEOUT>

    new(bus: flip I2CBus)
    {
        this.master = new I2CMaster<BUS_FREQUENCY, STRETCH_TIMEOUT>(bus)
    }
    // Camera-specific 16-bit register transactions delegate byte commands here.
}
```

A consumer may instantiate `CameraRegisterBus<50000Hz, 2ms>` in its clock context.
At 50 MHz, the default 100 kHz rate uses a 250-tick phase count; at 100 MHz it
uses 500 ticks. `HalfPeriodTicks()` exposes the derived count. State transitions,
line sampling and clock stretching lengthen wire periods, so the selected bus
frequency is a ceiling, not a guarantee of exact throughput.

The timeout bounds each continuous wait for released SCL to be observed high;
it is not a deadline for the whole transaction. On expiry the master releases
both low-drive requests, clears the ACK/data result, completes the command and
sets `HasTimedOut()`. `WasAckReceived()` and `WasNackReceived()` both return
false for that timeout. Check timeout status before consuming byte results.
A newly accepted command or `ClearResult()` clears timeout status. A new command
can proceed once the target releases SCL; a still-stuck clock times out again.
The controller does not generate recovery pulses or guarantee STOP on a stuck bus.

These settings are available in 1.3.0. Version 1.2.0 used fixed timing and had
no clock-stretch timeout. See the [migration notes](../CHANGELOG.md#upgrading-from-120).

## Physical Pins

Use `I2COpenDrainPins` when a component is connected to board-level `scl` and
`sda` pins.

```livt
using Livt.IO

component BoardI2CMaster
{
    pins: I2COpenDrainPins
    master: I2CMaster

    new(scl: inout logic, sda: inout logic)
    {
        this.pins = new I2COpenDrainPins(scl, sda)
        this.master = new I2CMaster(this.pins)
    }
}
```

Use `I2CBusCombiner` when a controller and target live in the same design or
test. The combiner performs the wired-AND behavior before the bus reaches the
physical adapter.

```livt
using Livt.IO

component LocalI2CTestRig
{
    pins: I2COpenDrainPins
    combiner: I2CBusCombiner
    master: I2CMaster
    slave: I2CSlave

    new(scl: inout logic, sda: inout logic)
    {
        this.pins = new I2COpenDrainPins(scl, sda)
        this.combiner = new I2CBusCombiner(this.pins)
        this.master = new I2CMaster(this.combiner.controller)
        this.slave = new I2CSlave(this.combiner.target, 0x42)
    }
}
```

## Master Command Flow

`I2CMaster` is asynchronous. Each `Begin*` method starts one bus command and
returns `false` if another command is already running. After a command starts,
wait until `HasResult()` is true, check `HasTimedOut()`, consume a successful
result, and call `ClearResult()`
before starting the next command. Address helpers take unshifted 7-bit addresses
in the range `0x00..0x7F`; `BeginWriteAddress` and `BeginReadAddress` return
`false` for invalid addresses.

```livt
using Livt.IO

component SensorWriter
{
    pins: I2COpenDrainPins
    master: I2CMaster

    new(scl: inout logic, sda: inout logic)
    {
        this.pins = new I2COpenDrainPins(scl, sda)
        this.master = new I2CMaster(this.pins)
    }

    public fn BeginStart() bool
    {
        return this.master.BeginStart()
    }

    public fn BeginWriteAddressCommand(deviceAddress: byte) bool
    {
        if (this.master.BeginWriteAddress(deviceAddress) == false) {
            return false
        }

        return true
    }
}
```

Application components usually wrap these byte-level commands in a higher-level
transaction FSM:

1. `BeginStart()`
2. `BeginWriteAddress(address)` and require ACK
3. `BeginWriteByte(registerAddress)` and require ACK
4. `BeginWriteByte(value)` and require ACK
5. `BeginStop()`

For reads from register-style devices, use a repeated START:

1. `BeginStart()`
2. `BeginWriteAddress(address)` and require ACK
3. `BeginWriteByte(registerAddress)` and require ACK
4. `BeginStart()`
5. `BeginReadAddress(address)` and require ACK
6. `BeginReadByte(true)` for all but the last byte
7. `BeginReadByte(false)` for the final byte
8. `BeginStop()`

The final read uses `sendAck = false` so the target sees a NACK and stops
preparing more bytes.

## Custom Target From I2CSlave

Use `I2CSlave` when you want to build a specific device protocol rather than a
plain register map. The component exposes persistent events for address matches,
received bytes, read requests, STOP detection, and transmitted-byte ACK/NACK.

```livt
using Livt.IO

component StatusByteTarget
{
    pins: I2COpenDrainPins
    slave: I2CSlave
    status: byte
    lastCommand: byte

    new(scl: inout logic, sda: inout logic)
    {
        this.pins = new I2COpenDrainPins(scl, sda)
        this.slave = new I2CSlave(this.pins, 0x42)
        this.status = 0x80
        this.lastCommand = 0x00
    }

    public fn SetStatus(value: byte)
    {
        state {
            this.status = value
        }
        this.slave.SetTransmitByte(value)
    }

    process ServiceI2C()
    {
        if (this.slave.HasReceivedByte()) {
            var value: byte = this.slave.GetReceivedByte()
            this.slave.ClearReceivedByte()
            state {
                this.lastCommand = value
            }
        }

        if (this.slave.IsReadRequested()) {
            this.slave.ClearReadRequested()
            this.slave.SetTransmitByte(this.status)
        }

        if (this.slave.HasStopDetected()) {
            this.slave.ClearStopDetected()
            this.slave.ClearAddressMatch()
        }
    }
}
```

For multi-byte reads, call `SetTransmitByte(firstByte)` for the current byte and
`SetNextTransmitByte(nextByte)` for the byte that should become active after the
master ACKs.

## Register Target

Use `I2CRegisterSlave` for the common "first write byte selects a register,
following bytes write data, repeated-start read returns data" pattern.

```livt
using Livt.IO

component RegisterDevice
{
    pins: I2COpenDrainPins
    registers: I2CRegisterSlave

    new(scl: inout logic, sda: inout logic)
    {
        this.pins = new I2COpenDrainPins(scl, sda)
        this.registers = new I2CRegisterSlave(this.pins, 0x42)
        this.registers.SetRegister(0x00, 0x80)
        this.registers.SetRegister(0x01, 0x00)
    }

    public fn SetStatus(value: byte)
    {
        this.registers.SetRegister(0x00, value)
    }

    public fn GetControl() byte
    {
        return this.registers.GetRegister(0x01)
    }

    public fn HasControlWrite() bool
    {
        return this.registers.HasWrittenRegister()
    }
}
```

Write transaction example from an external master:

- START
- write address `0x42`
- write byte `0x01`
- write byte `0x7F`
- STOP

This stores `0x7F` in register `0x01`.

Read transaction example:

- START
- write address `0x42`
- write byte `0x00`
- repeated START
- read address `0x42`
- read byte with ACK
- read byte with NACK
- STOP

This reads register `0x00`, then register `0x01`. ACKed bytes advance the
register pointer; the final NACK leaves the pointer at the last transmitted
register.

## Current Caveats

The current I2C components are reusable library building blocks, not a complete
implementation of every I2C mode.

- Timing inherits the consumer clock and supports configurable standard-mode rates.
- Only 7-bit addressing is implemented. Master address helpers reject values
  above `0x7F`; target constructors store the low seven address bits.
- The master is single-controller; it does not implement arbitration or
  multi-master recovery.
- 10-bit addressing is not implemented.
- High-speed mode, fast mode, and fast-mode plus timing are not configurable yet.
- Clock stretching is handled by counting SCL high time only while observed SCL
  is high. A configurable timeout releases the lines, but automatic bus-recovery
  pulses are not implemented.
- `I2CBusCombiner` currently models one controller-side and one target-side
  attachment. More targets need cascaded combiners or a future resolved-line bus
  helper.
- `I2CRegisterSlave` is an 8-bit register pointer and 256-byte register map.
  Wider register addresses or word registers should be implemented as wrappers.
- `I2CSlave` and `I2CRegisterSlave` expose byte-level events. Device-specific
  protocols should wrap them in a higher-level component FSM.

Useful future improvements:

- Multi-target bus helper with an array or variadic attachment style.
- Optional recovery clock pulses for stuck targets.
- Optional 10-bit addressing support.
- Transaction-level master helpers for common register read/write sequences.
- Wider or typed register-file helpers built on `I2CSlave`.
