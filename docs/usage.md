# Livt.IO Usage

## RAM

```livt
using Livt.IO

component MemoryExample
{
    ram: Ram

    new()
    {
        this.ram = new Ram()
    }

    public fn StoreAndLoad(address: int, value: byte) byte
    {
        this.ram.WriteByte(address, value)
        return this.ram.ReadByte(address)
    }
}
```

`Ram` has 2048 cells. Reads outside `0..2047` return `0x00`; writes outside
that range are ignored.

## UART Byte Send and Receive

```livt
using Livt.IO

component SerialExample
{
    uart: Uart

    new(rx: in logic, tx: out logic)
    {
        this.uart = new Uart(rx, tx)
    }

    public fn SendByte(value: byte) bool
    {
        return this.uart.Transmit(value)
    }

    public fn PollByte() byte
    {
        if (this.uart.IsDataAvailable())
        {
            return this.uart.Receive()
        }
        return 0x00
    }
}
```

## Buffered Send

```livt
using Livt.IO

component MessageExample
{
    uart: Uart

    new(rx: in logic, tx: out logic)
    {
        this.uart = new Uart(rx, tx)
    }

    public fn SendOk() bool
    {
        var message = "OK\n".Encode()
        return this.uart.Send(message)
    }
}
```

`Send(data)` only queues the message when the transmit FIFO has space for every
byte.

## Loopback Serial

```livt
using Livt.IO

@Test
component LoopbackExampleTest
{
    uart: LoopbackUart

    new()
    {
        this.uart = new LoopbackUart()
    }

    @Test
    fn EchoesByte()
    {
        this.uart.Transmit(0x42)
        Simulation.Wait(UartTransmitter.TICKS_PER_BIT * 12)
        assert this.uart.Receive() == 0x42
    }
}
```

## I2C Master

See [`i2c.md`](i2c.md) for complete I2C wiring, transaction, register-slave,
and caveat examples. The snippets below show the smallest direct component
shapes.

```livt
using Livt.IO

component I2cWriter
{
	pins: I2COpenDrainPins
	master: I2CMaster

	new(scl: inout logic, sda: inout logic)
	{
		this.pins = new I2COpenDrainPins(scl, sda)
		this.master = new I2CMaster(this.pins)
	}

	public fn BeginWriteRegister(deviceAddress: byte, value: byte) bool
	{
		if (this.master.IsBusy()) {
			return false
		}

		this.master.BeginStart()
		return true
	}
}
```

`I2CMaster` commands are asynchronous. `BeginStart`, `BeginStop`,
`BeginWriteByte`, and `BeginReadByte` return `false` when the master is already
busy. Poll `IsBusy()` and `HasResult()` before reading `WasAckReceived()` or
`GetReadByte()`.

## I2C Slave

```livt
using Livt.IO

component I2cBytePeripheral
{
	pins: I2COpenDrainPins
	slave: I2CSlave

	new(scl: inout logic, sda: inout logic)
	{
		this.pins = new I2COpenDrainPins(scl, sda)
		this.slave = new I2CSlave(this.pins, 0x42)
	}

	public fn PollReceivedByte() byte
	{
		if (this.slave.HasReceivedByte()) {
			var value: byte = this.slave.GetReceivedByte()
			this.slave.ClearReceivedByte()
			return value
		}

		return 0x00
	}
}
```

For a controller and target in the same design, insert `I2CBusCombiner` between
`I2COpenDrainPins` and the devices. The combiner owns public `controller` and
`target` endpoints:

```livt
this.pins = new I2COpenDrainPins(scl, sda)
this.combiner = new I2CBusCombiner(this.pins)
this.master = new I2CMaster(this.combiner.controller)
this.slave = new I2CSlave(this.combiner.target, 0x42)
```

The combiner ORs active-low drive requests before they reach the physical
adapter and propagates observed line levels back to both attachments.

## I2C Register Slave

```livt
using Livt.IO

component I2cStatusDevice
{
	pins: I2COpenDrainPins
	registers: I2CRegisterSlave

	new(scl: inout logic, sda: inout logic)
	{
		this.pins = new I2COpenDrainPins(scl, sda)
		this.registers = new I2CRegisterSlave(this.pins, 0x42)
		this.registers.SetRegister(0x00, 0x80)
	}

	public fn SetStatus(value: byte)
	{
		this.registers.SetRegister(0x00, value)
	}

	public fn GetControl() byte
	{
		return this.registers.GetRegister(0x01)
	}
}
```

`I2CRegisterSlave` treats the first write byte as the register pointer. Later
write bytes store values into the current register and advance the pointer, so a
master can write `0x01, 0x7F` to set register `0x01` to `0x7F`. Reads return the
current register value prepared through the underlying `I2CSlave`; ACKed
read bytes advance the pointer for repeated multi-byte reads.
