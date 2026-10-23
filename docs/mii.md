# MII Ethernet — Livt.IO 1.4.0

`MiiAdapter` connects the existing `EthernetReceiver` and `EthernetTransmitter`
to a full-duplex MII PHY. `Dp83848Phy` manages the DP83848 family through the
existing Clause-22 `MdioController`, advertising 10 and 100 Mb/s full duplex.
Half-duplex and pause are not advertised. PHY identity is checked before writes;
management failures revoke readiness and retry. Board logic supplies reference
clock, hardware reset, and startup permission.

## Package and construction

```toml
[dependencies]
"Livt.IO" = "1.4.0"
```

Construction fragment inside a component whose context runs at 50 MHz:

```livt
this.mdio = new MdioController(mdioPins)
this.phy = new Dp83848Phy(mdio, startupReady, restart)
this.media = new MiiAdapter(this.context, receiveContext, transmitContext, pins, phy)
```

Import `Livt.IO` and `Livt.IO.Phy`. The board supplies `IMiiPins`, `IMdioPins`,
RX/TX clock contexts, startup permission, and a restart toggle. Share the media
and link status with the MAC receiver/transmitter. The executable
[100 Mb/s fixture](../tests/ethernet/Mii100Test.lvt) shows the media wiring.

## Domains and ownership

Construct `MiiAdapter(macContext, receiveContext, transmitContext, pins, link)`.
The MAC context is 50 MHz. RX and TX contexts follow the PHY clocks: 25 MHz at
100 Mb/s and 2.5 MHz at 10 Mb/s. Context timing metadata must not be used as a
runtime speed detector; wire serialization advances once per media clock edge.
The PHY manager supplies resolved speed. The board must assert all resets
together and release each synchronously, including when a media clock stops.

The adapter implements `IEthernetMedia`. It owns two 2048-entry, 11-bit FIFOs
requesting block RAM through `Livt.Collections.AsyncFifo`. Tokens include byte
and boundary/error flags. Payload RAM is not reset. Check target synthesis
reports for actual memory mapping.

TX accepts one complete wire frame, including preamble/SFD/FCS, before starting
serialization. Admission is paced at one byte per four MAC cycles to preserve
the existing MAC synchronous-RAM read contract. `txReady` describes buffer admission; `txDone` arrives only after
physical TX completion. The serializer maintains a 96-bit interframe gap at
both speeds. An aborted partial frame is drained without transmission. Link
loss or producer abort after commit marks the transaction failed even if the
serializer finishes draining the frame. Reset is required to recover if a PHY
clock permanently stops before acknowledging completion.

RX cannot backpressure the PHY. Odd nibble counts, RX_ER, or FIFO overflow mark
the frame bad; a terminating error token prevents joining it to the next frame.
The existing MAC validates preamble/FCS, length, and destination filtering.

## Physical constraints

Constrain RX/TX pins against PHY clocks. Bound both Gray pointer buses and
synchronize mailbox/clear controls; do not blanket-false-path the entire FIFO.
The DP83848 datasheet is available at https://www.ti.com/lit/gpn/dp83848j .
A board must supply its own I/O timing and clock/reset constraints.

## Verification

`livt test -R` runs 10/100 clock-domain loopback, repeated
frames, abort/reuse, receive errors, odd nibble counts, overflow, and PHY recovery.
These tests are behavioral verification, not board timing qualification.

The MII fixtures are ordinary files in `tests/ethernet`, listed in `livt.toml`.
Run one case with `livt test -R -r Mii100Test` or
`livt test -R -r Dp83848PhyTest`.
