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
wait until `HasResult()` is true, consume the result, and call `ClearResult()`
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

- Timing is fixed to 100 MHz source clock and 100 kHz standard mode.
- Only 7-bit addressing is implemented. Master address helpers reject values
  above `0x7F`; target constructors store the low seven address bits.
- The master is single-controller; it does not implement arbitration or
  multi-master recovery.
- 10-bit addressing is not implemented.
- High-speed mode, fast mode, and fast-mode plus timing are not configurable yet.
- Clock stretching is handled by counting SCL high time only while observed SCL
  is high, but there is no timeout or bus-recovery policy.
- `I2CBusCombiner` currently models one controller-side and one target-side
  attachment. More targets need cascaded combiners or a future resolved-line bus
  helper.
- `I2CRegisterSlave` is an 8-bit register pointer and 256-byte register map.
  Wider register addresses or word registers should be implemented as wrappers.
- `I2CSlave` and `I2CRegisterSlave` expose byte-level events. Device-specific
  protocols should wrap them in a higher-level component FSM.

Useful future improvements:

- Generic timing constants or clock-frequency configuration.
- Multi-target bus helper with an array or variadic attachment style.
- Optional clock-stretch timeout and bus recovery.
- Optional 10-bit addressing support.
- Transaction-level master helpers for common register read/write sequences.
- Wider or typed register-file helpers built on `I2CSlave`.
