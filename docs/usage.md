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

## RTS/CTS Buffered Send

Use `RtsCtsUart` when the board exposes conventional active-low hardware flow
control pins:

```livt
using Livt.IO

component FlowControlledSerialExample
{
    uart: RtsCtsUart

    new(rx: in logic, tx: out logic, cts_n: in logic, rts_n: out logic)
    {
        this.uart = new RtsCtsUart(rx, tx, cts_n, rts_n)
    }

    public fn SendMessage(data: byte[]) bool
    {
        return this.uart.Send(data)
    }
}
```

The transmitter starts a queued frame only while `cts_n` is low. Releasing CTS
during a frame does not corrupt that frame; transmission pauses before the next
one. The UART drives `rts_n` high before its receive FIFO fills and drives it low
again after enough data has been consumed.

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

## SPI Master

`SPIMaster` consumes a flipped `SPIBus` attachment. A board-level provider or
test fixture owns the bus and connects it to physical signals.

```livt
using Livt.IO

component FlashByteReader
{
	master: SPIMaster

	/**
	 * Creates a byte reader attached to one SPI flash bus.
	 */
	new(bus: flip SPIBus)
	{
		this.master = new SPIMaster(bus)
	}

	/**
	 * Reads one byte with command 0x03 and a 24-bit flash address.
	 */
	public fn ReadByte(address: int) byte
	{
		while (!this.master.BeginSelect()) {
			state {}
		}
		while (this.master.IsBusy()) {
			state {}
		}

		this.Transfer(0x03)
		this.Transfer((address >> 16) as byte)
		this.Transfer((address >> 8) as byte)
		this.Transfer(address as byte)
		var value = this.Transfer(0x00)

		while (!this.master.BeginDeselect()) {
			state {}
		}
		while (this.master.IsBusy()) {
			state {}
		}

		return value
	}

	/**
	 * Exchanges one byte while preserving the active transaction.
	 */
	fn Transfer(value: byte) byte
	{
		while (!this.master.BeginTransfer(value)) {
			state {}
		}
		while (this.master.IsBusy()) {
			state {}
		}

		return this.master.GetReceivedByte()
	}
}
```

The example keeps chip select asserted across the command, address, and data
byte, then completes the transaction with `BeginDeselect()`. Additional
`Transfer(0x00)` calls can be inserted before deselection for sequential reads.

The master derives its 50 ns SCLK half-period from the context it inherits
during construction. Place the containing component in the desired clock
context so construction and the controller process use the same domain.
