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
