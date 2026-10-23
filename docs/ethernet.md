# Ethernet contracts

Livt.IO provides buffered Ethernet receive/transmit engines, a media interface,
RMII and MII adapters, MDIO transport and PHY management components. This document
describes their configuration, ownership rules and integration requirements.

## Scope and layering

`RmiiAdapter<ENABLE_10>` uses one 50 MHz clock/reset context. Its default mode
is 100 Mbit/s; `ENABLE_10 = true` also admits 10 Mbit/s with a compatible link
manager. Both RMII rates have been exercised on hardware in consumer designs.

Livt.IO 1.4.0 adds [MII and DP83848 support](mii.md), with independent RX/TX
clocks and focused simulation coverage at both 10 and 100 Mbit/s. This does not
transfer the RMII hardware results to the new MII implementation.
Half-duplex, VLAN-tagged frames, jumbo frames and pause-frame flow control are
not supported. Ethernet transport does not imply an IP,
UDP or TCP stack.

Public declarations live in `Livt.IO`, under `src/ethernet`:

| Contract | Provider / responsibility |
| --- | --- |
| `IEthernetReceiver` | Complete-frame storage and scheduled RX ownership/read API |
| `IEthernetTransmitter` | Scheduled TX fill/commit and local completion API |
| `IEthernetMedia` | Replaceable RMII/MII adapter, raw octets and wire boundaries |
| `IRmiiPins` | Physical RMII signals viewed from the FPGA adapter |
| `IMiiPins` | MII data/control signals; RX/TX contexts are supplied separately |
| `IMdioPins` | Split input/output/output-enable management pins |
| `IEthernetLinkStatus` | PHY manager's coherent ready/rate outputs |
| `EthernetResult` | Immediate application-operation result |
| `EthernetTransmitOutcome` | Retained local transmit completion |
| `EthernetSpeed` | Unknown, 10 Mbit/s, or 100 Mbit/s |
| `EthernetReceiveDiscard` | Classified receive-drop counters |

Implemented constructors are:

| Component | Constructor / configuration |
| --- | --- |
| `EthernetTransmitter<CAPACITY = 1514>` | `(media: flip IEthernetMedia, link: IEthernetLinkStatus)` |
| `EthernetReceiver<CAPACITY = 1514, PROMISCUOUS = false>` | `(media: IEthernetMedia, link: IEthernetLinkStatus, localMac: byte[6])` |
| `RmiiAdapter<ENABLE_10 = false>` | `(pins: IRmiiPins, media: IEthernetMedia, link: IEthernetLinkStatus)` |
| `MdioController` | `(pins: IMdioPins)`, implements `IMdioController.Read/Write` |
| `Livt.IO.Phy.Rtl8201Phy<PHY_ADDRESS = 1, POLL = 10ms>` | `(mdio: IMdioController, startupReady: bool)`, implements `IEthernetLinkStatus` |
| `Livt.IO.Phy.Rtl8211Phy<PHY_ADDRESS = 1, POLL = 10ms>` | `(mdio: IMdioController, startupReady: bool, restart: bool)`, implements `IEthernetLinkStatus` |

The buffered receiver/transmitter own independent `SynchronousRam` instances
with block-memory intent, capacity-derived address widths and no payload reset.
The transmitter reads ahead of each byte slot; the receiver drains a four-byte
FCS tail and schedules application reads through the RAM port. The API copies
bytes and never hands out a mutable RAM reference. RX/TX capacities are 60..1514.
Framing and RMII constructors assert a 50 MHz context. All API calls have one
serialized application owner; MDIO has one serialized management owner.

Use the same media signal bundle for the RMII adapter and two MAC engines.
The adapter drives `txReady/txDone/txFault` and the RX signals, while TX drives
`txData/txValid/txFirst/txLast/txAbort`; RX only observes it. Supply `localMac: byte[6]` as stable constructor configuration. The PHY
reset supervisor supplies `startupReady` after the reference clock and hardware
reset sequence are complete.

Generic MDIO transport belongs to `Livt.IO`; PHY-specific configuration lives
under `Livt.IO.Phy`. `Rtl8201Phy` manages an RMII PHY, while
[`Rtl8211Phy`](rtl8211.md) manages an RTL8211F with RGMII. PHY management does not
provide a media adapter. The integrating application supplies any FPGA primitives,
tri-state pads, reset sequencing, pin assignments, clocks and timing constraints.
MAC framing is independent of the PHY register configuration and FPGA vendor.

Livt.Net adapts these IO APIs through `Livt.Net.Drivers.Ethernet`
[`EthernetFrameReceiver` and `EthernetFrameTransmitter<S>`](../../livt-net/docs/ethernet.md).
They reuse Net's existing frame capabilities and ARP/ICMP services. IO has no
dependency on Net or `IPacketData`.

## Frame representation and filtering

- Bytes begin at destination MAC, followed by source MAC, EtherType and payload.
- Application data excludes preamble, SFD and the four-byte FCS.
- TX accepts 14..1514 supplied bytes, further bounded by configured TX capacity.
  The caller supplies a complete 14-byte Ethernet II header, including source MAC.
- The MAC alone owns missing minimum-frame padding: zero-extend supplied data to
  60 bytes before calculating FCS. Already padded frames receive no extra padding.
- RX accepts 60..1514 bytes excluding FCS, further bounded by RX capacity. The
  entire frame must fit. No truncated prefix is published.
- RX retains padding. Ethernet II has no generic payload-length field, so the
  MAC must not guess how many trailing bytes to strip.
- Accept EtherType values at least `0x0600`, except `0x8100` and `0x88A8`, which
  are rejected as unsupported tag formats. Values below `0x0600` are unsupported
  (including IEEE 802.3 length frames). Do not parse tag stacks or remove tags.
- Default RX filtering accepts the configured local destination address and
  broadcast. Compile-time promiscuous mode also admits other destinations,
  including multicast. It never bypasses length, format, PHY-error or FCS checks.
- TX does not rewrite/filter destination or source addresses. Upper layers own
  address selection. Other than supported EtherType validation, the MAC does not
  interpret payloads or implement pause frames.

RX and TX each configure their own `CAPACITY` at compile time in 60..1514,
defaulting to 1514. RX also configures `PROMISCUOUS`, defaulting to false.
The constructor-bound `localMac: byte[6]` remains stable until coordinated reset.
A smaller capacity reduces the maximum supported frame, not its capture
completeness. There is one buffer slot per direction and no runtime MAC-address
update API.

## Scheduled application API

One serialized service owner operates each RX/TX API in its provider's clock/reset
context. RX and TX owners may run concurrently. Calls are scheduled interactions;
no call is promised to finish in one cycle. Snapshot getters reserve nothing.
No token, reference counting, dynamic provider selection, or implicit CDC is added.

`EthernetResult.Success` means an immediate operation succeeded; `Accepted` is
reserved for TX commit. `Busy` means storage is owned elsewhere; `NotReady`
means unavailable data/link/initialization; `Invalid` means wrong lifecycle or
incomplete input; `Unsupported` means a size/format outside the contract;
`DeviceFailure` means a local device/storage failure. Rejected operations preserve
storage and ownership. An `out` byte on a failed read is always zero; a failed
completion query always assigns `EthernetTransmitOutcome.None`.

### RX ownership

`Free -> Receiving -> Published -> Acquired -> Free`.

Only publish after a complete valid frame and successful storage. An invalid
receive event returns to Free. If storage is Published/Acquired at frame start,
discard that entire incoming event even if the application releases midway.

| Method | Contract |
| --- | --- |
| `GetReceiveCapacity()` | Allocated capacity, independent of current frame |
| `HasReceiveFrame()` | True while Published or Acquired |
| `TryAcquire()` | Success: Published becomes Acquired; Busy: already Acquired; DeviceFailure: no published frame and sticky local capture failure; otherwise NotReady |
| `GetReceiveLength()` | Exact acquired length excluding FCS; zero outside Acquired |
| `TryRead(index, value)` | Success only in Acquired and `0 <= index < length`; otherwise Invalid and zero; local storage failure returns DeviceFailure and zero |
| `TryRelease()` | Success: Acquired becomes Free; otherwise Invalid |
| `HasReceiveError()` | Sticky local storage/capture failure; ordinary wire drops are counters instead |
| `TryAcknowledgeReceiveError()` | Success clears sticky error; NotReady if absent; a same-edge new failure wins over acknowledgment |
| `GetDiscardCount(reason)` | Saturating unsigned 32-bit counter, cleared only by coordinated reset |

A valid published/acquired frame takes priority over a previously latched capture
error. Acknowledging an error does not release a frame or erase discard counters.
Link loss and rate changes discard incomplete RX but preserve Published/Acquired
frames. Read access and release do not require an active link.

Classify each discarded receive event once, using this precedence:
`BufferFull`, `PhysicalError`, `InvalidLength`, `BadFcs`, `UnsupportedFrame`,
`Filtered`. BufferFull means no slot at the start and does not claim valid CRC.
PhysicalError includes link interruption, incomplete octets and malformed
preamble/SFD. InvalidLength includes runts, oversize and configured-capacity
excess. A local storage failure instead sets the sticky device error and discards
unpublished data; it is not misreported as a wire-error counter. Aborting on reset
produces no event because reset clears state and diagnostics.

### TX ownership

`Free -> Filling -> Committed -> Transmitting -> Completion pending -> Free`.

| Method | Contract |
| --- | --- |
| `GetTransmitCapacity()` | Maximum supplied frame length; generated padding/FCS need no application storage |
| `TryBegin(length)` | Success reserves Free storage for exactly length bytes; Busy if any fill/commit/completion occupies it; NotReady if link unavailable; Unsupported outside 14..capacity |
| `TryAppend(value)` | Success appends to the initialized prefix while Filling; Invalid otherwise or when declared length reached |
| `TryCommit()` | Accepted only with exactly the declared bytes and supported EtherType; Invalid for absent/incomplete fill; Unsupported for format; NotReady for unavailable link |
| `TryDiscard()` | Success releases Filling; Busy for committed/transmitting/completion work; Invalid if Free |
| `TryGetCompletion(outcome)` | Success returns a retained terminal outcome; otherwise NotReady and None |
| `TryAcknowledgeCompletion()` | Success clears a retained result and frees storage; otherwise NotReady |

For Begin, occupied storage takes priority over link and length checks. For
Commit, committed/transmitting/completion work returns Busy; then check fill
presence/completeness, format, and link readiness in that order. Local failure
returns DeviceFailure when an otherwise legal operation cannot be performed.

Begin/Append copy caller data; they never borrow an external provider. Failed
Commit keeps Filling ownership so the owner can retry when link returns or
Discard. Link loss while Filling likewise preserves the partial fill. Appending
or discarding a fill does not require link readiness. Append-only construction
prevents holes and commits of uninitialized RAM.

After Accepted, application mutation is forbidden. The engine emits a complete
frame without application calls. There is no cancellation after commit. Completion
is latched exactly once and blocks subsequent Begin until acknowledged:

- `Sent`: final FCS symbol has completed at the MAC/PHY interface. Neither remote
  receipt nor physical-cable success is implied. The next frame still waits for
  the inter-frame gap even if this result is already acknowledged.
- `LinkLost`: link becomes unusable or rate changes before local completion;
  queued committed frames fail too. No automatic retry.
- `DeviceFailure`: local storage/serialization fault; no successful transmission
  is claimed. An already emitted prefix cannot be withdrawn.

Link loss takes priority over a coincident successful finish, then device fault,
then Sent. Failure is published only once the engine is locally quiescent and no
more bytes from that frame can be emitted. Retained outcomes survive subsequent
link changes. All outcomes become None on coordinated reset.

## Signal datapath and PHY boundaries

`IEthernetMedia` directions are from the media adapter's perspective. The MAC
supplies `txData/txValid/txFirst/txLast/txAbort` and consumes adapter outputs.
All acceptance/events are sampled at the shared rising context edge. There are
no scheduled methods on this boundary.

The stream contains raw frame octets INCLUDING preamble, SFD and FCS. The MAC
owns framing, CRC, padding, validation and the 96-bit-time inter-frame gap;
the adapter owns RMII symbol timing and byte assembly. The adapter supplies a
byte-slot enable rather than buffering application transactions.

- TX accepts one octet when `txValid && txReady`. Data and First/Last remain
  stable while valid is asserted without ready. First marks the first preamble
  octet; Last marks the final FCS octet. Markers have meaning only on acceptance.
- Ready indicates an available octet launch slot. During an active frame, the MAC
  must supply the next byte for every such slot. Missing valid is an underrun:
  adapter aborts and pulses txFault; it must never pause an active wire frame.
- Between octet slots the adapter serializes the held byte. The RMII
  cadence is four 50 MHz clocks per octet at 100 Mbit/s and forty at 10 Mbit/s.
- `txDone` pulses for one cycle at the first boundary after the complete last
  symbol interval. Accepting Last alone is not completion. No next First may
  be accepted until the MAC has preserved the full inter-frame gap after Done.
- `txAbort` overrides acceptance, drops pending serialization and requests idle.
  The adapter reports one txFault when an active frame becomes quiescent. Abort
  with no active frame emits no terminal event. Done and Fault are exclusive.
- RX has no ready signal. Start pulses with the first valid preamble octet.
  Valid marks each assembled octet. End pulses once, either with the final valid
  octet or later; process that octet before finalizing length/FCS. Error may pulse
  anywhere through End and is latched for the event. Start and End for different
  events must not coincide.
- A malformed carrier event with no complete octet is represented by simultaneous
  Start/End/Error with Valid false. It must not be interpreted as a valid frame.
- The adapter decodes standard CRS_DV, including its end-of-carrier toggling; it
  does not depend on a vendor-specific RXDV remapping. RX ends with Error on link
  interruption. Reset suppresses all pending events and drives TX inactive.

`IRmiiPins` is viewed from the FPGA: rxData/crsDv/rxError are inputs;
txData/txEnable are outputs. If RX_ER is unavailable, the integrating wrapper binds
rxError low and documents the lost diagnostic. CRC and other checks still apply.
Reference clock/reset are context bindings outside this interface; no assumption
is made that the FPGA sources the PHY reference clock.

`IMdioPins` splits the bidirectional pad into input, output and output-enable.
The pad adapter drives Z whenever output-enable is false. The controller owns
turnaround timing and MDC. PHY reset timing and straps are external integration requirements.

`IEthernetLinkStatus` is produced in the same context as the MAC. Ready is false
at reset and until the PHY reports a supported resolved full-duplex mode. Speed
is Unknown whenever not ready. Changing rates must include at least one sampled
edge with Ready false; an application must not synchronize speed bits separately
from readiness. Management traffic can use context clock enables rather than a
second generated fabric clock.

## Storage, reset and throughput

The implementation owns one single-clock, single-port RX RAM and a separate
TX RAM. RX writes while Receiving and serves application reads only while
Acquired. TX fills before Committed and reads only after commit. Therefore each
RAM has one owner at a time, while independent RAMs allow RX and TX to overlap.
The transmitter must prefetch with the synchronous RAM latency accounted for;
the byte-slot timing is not a scheduled RAM-method timing promise.

Default payload allocation is 2 * 1514 bytes, plus metadata, CRC state and
serialization registers. Physical memory and logic usage depend on the target and synthesis tool.
Use uninitialized payload storage; reset clears ownership/length/status, not all
RAM cells. Compile-time capacities determine RAM address widths; bounded control counters
currently use Livt integer fields.

All consumers and providers participate in one coordinated reset. Reset abandons
calls, fills, acquired data, committed work and terminal results; callers must
stop using old references. No completion is manufactured for reset-aborted work.
After reset, RX has no published/acquired frame, no receive error and zero
length; TX has no completion. TX admission returns NotReady until the link is
usable. Scheduled calls respect component constructor startup. Capacity getters
retain their configuration.

A 100 Mbit/s link represents a raw 12.5 MB/s byte rate per direction, including
wire overhead, not guaranteed application payload throughput. One RX slot loses
frames while its predecessor is published/acquired; one TX slot introduces fill
latency between frames. Scheduled calls and upper-layer parsing have additional costs.
No lossless minimum-gap application service claim is made. Continuous media handling is distinct from application admission/drop behavior.

Independent application clocks require an explicit clock-domain crossing adapter.
Ordinary per-byte `sync` calls
are not a throughput solution; current IO single-clock RAM/FIFO contracts do not
imply dual-clock RAM or asynchronous FIFO support.

## Integration with Livt.Net

The Net transmitter adapter has its own state and a statically bound `IPacketData`
source. It must preserve the existing [frame-link contract](../../livt-net/docs/frame-link.md).

| Net capability | Mapping |
| --- | --- |
| RX acquire/release | Delegate IO lifecycle, map immediate results |
| `IPacketData` ready/length/reads | Ready only while acquired; exact IO length; map no acquisition to PacketDataResult.NotReady, bad index or local read failure to Invalid (zero output), and expose the latter through sticky receive error |
| Known wire length | True only while acquired; equal to available length, excluding FCS |
| RX capture errors | Map sticky local IO failure; wire-drop counters do not poison every acquire |
| TX minimum/maximum | Retain Net's minimum 60; maximum equals IO capacity |
| `TrySubmit()` | Check prepared source and bounds, reserve IO fill, then return Accepted and begin the source borrow |
| Copy progress | Scheduled source reads append bytes into IO; commit only after complete copy |
| Source read/commit failure | Discard uncommitted fill, stop reads, then latch DeviceFailure |
| Completion | Map IO Sent to Net Delivered; LinkLost/DeviceFailure to Net DeviceFailure |
| Borrow lifetime | Keep source/dependencies borrowed until a latched Net terminal result, even if copying ended earlier |
| Acknowledgment | Clear IO and adapter terminal state before accepting another source |
| Cancellation | Advertise false; TryCancel returns Unsupported without changing ownership |
| Reset | Use Net's coordinated reset barrier; never expose abandoned work as Delivered |

Net composers already supply minimum padding, which IO preserves. The adapter's Delivered occurs after local
wire-interface completion; the common Net capability retains its weaker meaning
of device acceptance and never promises remote delivery. Protocol-dependent RX
views must finish before release, including responses borrowing RX through TX.

## MDIO and PHY management

`MdioController` emits 64 MDC cycles per transaction, including all 32 preamble
ones. Its context-derived half-period is at least 500 ns; the extra drive/setup
state makes MDC slightly slower than 1 MHz. Reads release MDIO for both
turnaround bits and data, check the second turnaround bit is zero, and sample
immediately before raising MDC, after the previous PHY data launch has settled.
PHY data may advance within 0–300 ns after an MDC rising edge; sampling late in
the high phase reads the next bit and shifts the returned register word.
No response returns `DeviceFailure` with zero data; invalid 5-bit addresses
return `Invalid` without clocking. Write success means the local transaction
finished; Clause 22 has no write acknowledgment. The integrating application supplies the
tri-state pad and a suitable pull-up.

`Rtl8201Phy` waits for `startupReady` after PHY reset/clock startup.
It verifies IDs `001C/C81x`, preserves page-7 register-16 delay/reserved fields,
selects PHY-supplied REF_CLK and standard CRS_DV, advertises only 100BASE-TX full
duplex (`ANAR=0101`), disables EEE advertisement and restarts autonegotiation.
It reads BMSR twice, requires link/autonegotiation complete without remote fault,
and checks the link partner's acknowledged IEEE advertisement includes 100-full.
Missing/wrong PHY and management failures clear readiness and retry setup.
Unsupported/unfinished negotiation remains not ready. `failed` reports a
management/configuration failure; link-down alone is not a management failure.
Hardware reset sequencing is supplied externally.

The receiver's native RAM backend has no ECC/error output. `HasReceiveError`
is therefore false and its acknowledgment returns `NotReady`; invalid API reads
return `Invalid` and zero without changing acquired ownership. Wire discards
increment saturating counters with the documented precedence. No invalid or
partially received frame becomes readable. Reset invalidates metadata rather
than clearing cells, so stale bytes remain inaccessible.

`Rtl8201Phy` and `Rtl8211Phy` select 100 Mbit/s full duplex. `Dp83848Phy`
advertises both 10 and 100 Mbit/s full duplex for MII. Enabling 10 Mbit/s in the
RMII adapter also requires a link manager that admits that rate.

`MiiAdapter` supplies asynchronous FIFOs; RMII stays in one clock domain.
Physical pad wrappers, board timing constraints, and clock/reset distribution
remain board responsibilities. Half-duplex collision handling is not provided.
