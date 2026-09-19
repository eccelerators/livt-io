# Memory

## Choose the access contract first

| API | Read timing | Use |
|---|---|---|
| `Ram<T, CAPACITY = 64, STYLE = Auto>` / `IRam<T>` | Scheduled, multi-cycle | Application transactions |
| `BlockRam<T, CAPACITY = 2048>` | Same scheduled contract | Explicit block-style intent |
| `DistributedRam<T, CAPACITY = 64>` | Same scheduled contract | Explicit distributed-style intent |
| `SynchronousRam<T, ADDRESS, CAPACITY = 64, STYLE = Auto>` | One enabled edge | One operation per clock |
| `AsynchronousRam<T, ADDRESS, CAPACITY = 64, STYLE = Auto>` | Combinational | Live reads and clocked writes |
| `AsynchronousDistributedRam<T, ADDRESS, CAPACITY = 64>` | Combinational | Inherited Distributed specialization |

The hierarchy keeps access timing independent of resource intent:

```text
Ram<T, CAPACITY, STYLE> : IRam<T>
├── BlockRam<T, CAPACITY>
│   ├── Ram16
│   └── Ram32
└── DistributedRam<T, CAPACITY>

SynchronousRam<T, ADDRESS, CAPACITY, STYLE> : ISynchronousRam<...>

AsynchronousRam<T, ADDRESS, CAPACITY, STYLE> : IAsynchronousRam<...>
└── AsynchronousDistributedRam<T, ADDRESS, CAPACITY>
    ├── AsynchronousDistributedRam8x64
    ├── AsynchronousDistributedRam32x16
    └── AsynchronousDistributedRam32x32
```

`BlockRam` and `DistributedRam` own synchronous storage and expose scheduled
methods. The asynchronous subclasses inherit their payload and processes directly;
no forwarding component, port conversion, or additional clock boundary is added.

All names are in `Livt.IO`. Capacity counts elements, not bytes. Payloads must
be fixed-width synthesizable values supported by the memory compiler; tested
configurations include byte, uint, and 8-/16-/32-bit logic vectors. Capacity
must be positive and may be one or a non-power of two. Scheduled addresses are
`int`; invalid reads return zero and invalid writes are ignored.

```livt
using Livt.IO

component SampleStore
{
	// Sixty-four 16-bit elements with explicit block-style intent.
	storage: BlockRam<logic[16], 64>

	/**
	 * Constructs the store in the inherited clock/reset context.
	 */
	new()
	{
		this.storage = new BlockRam<logic[16], 64>()
	}

	/**
	 * Writes before reading; no startup value is assumed.
	 */
	public fn StoreAndLoad(address: int, value: logic[16]) logic[16]
	{
		this.storage.Write(address, value)
		return this.storage.Read(address)
	}
}
```

`Ram` derives a narrow internal address using `Bits.RequiredFor(CAPACITY - 1)`.
The low-level cores instead require an explicit unsigned ADDRESS type, normally
`logic[N]`. Supply at least that many bits (one for capacity one) and at most
32 bits, because the cores compare addresses as uint. The library does not
currently reject an undersized ADDRESS type: low-level callers own
that geometry check. `RamGeometry<CAPACITY>` prevents accidentally substituting
a provider with a different declared depth; it does not prove its behavior.

## Initialization, reset and concurrency

Every valid cell is **unspecified until written**. Reset retains payloads;
there is no automatic zero-fill or whole-array reset. To require initial zeros,
write every cell explicitly before enabling readers. Such initialization takes
multiple cycles. Queue lengths and valid-prefix metadata can instead keep
unwritten cells inaccessible, as in the migrated CLI buffers.

The synchronous port accepts a read or a write, never both, at an enabled rising
edge. Its read output holds during writes, disabled cycles and invalid accesses;
reset clears only the response and suppresses commands. The asynchronous port
reads continuously, including during reset; reset suppresses writes. After a
same-address write its read output reflects the new cell value. Invalid
asynchronous reads return zero. There is no independent second read address.

Scheduled Read and Write each serialize their callers. The shared `RamAccess`
owner alternates priority between pending reads and writes (write wins the first
tie after reset); a read reserves a
following edge to capture the response. Reset cancels pending calls. Already
committed writes remain committed; cancellation does not roll back storage.
Method dispatch costs more cycles than the storage edge contract. See the
[measured latency checks](../verification/memory/README.md).

## Storage intent and custom providers

Auto emits no placement attribute. Block and Distributed emit direct hints on
the array through `@Memory(Style=STYLE)`. They do not select different timing,
initialize memory, force physical mapping, or introduce a runtime selector.
In particular, asking for Block on an asynchronous core cannot give a device's
block RAM an unsupported combinational read port.

For a custom implementation, the composition root owns a provider implementing
`ISynchronousRam<T, ADDRESS, RamGeometry<CAPACITY>>` and passes it to
`RamAccess<T, ADDRESS, CAPACITY, ProviderType>`. It must use the same context,
have one exclusive command owner, and meet the one-edge/reset/hold contract.
The compiler checks the interface's payload, address and geometry identity;
behavioral compliance is the provider author's responsibility.

The provider may be Livt or an `@Opaque` component from a vendor-specific package.
This is a compile-time choice, not a runtime factory or virtual dispatch table.
[`RamBackendTest`](../tests/memory/RamBackendTest.lvt) tests the same access
adapter over the portable core and a test-only custom HDL backend. No vendor
SDK, synthesis report parser or handwritten production RAM is required.

## Migrating older RAM users

- Replace `Ram` / `new Ram()` with, for example, `Ram<byte, 2048>` /
  `new Ram<byte, 2048>()`. The generic default capacity is 64, not 2048.
- Replace `ReadByte` / `WriteByte` with `Read` / `Write`.
- `Ram16` and `Ram32` retain their Read/Write APIs and 2048-element capacities;
  they now inherit block-style generic RAM. Scheduled completion latency changes.
- Rename `DistributedRam8x64`, `DistributedRam32x16` and
  `DistributedRam32x32` to `AsynchronousDistributedRam8x64`,
  `AsynchronousDistributedRam32x16` and `AsynchronousDistributedRam32x32`.
  These inherit the generic asynchronous implementation; `DistributedRamPort`
  is removed, without compatibility aliases.
- Rename `write_enable`, `write_data`, and `read_data` to `writeEnable`,
  `writeData`, and `readData`. Write-enable is now bool: replace `0b1/0b0`
  with `true/false`. Address and data widths are unchanged.
- Wire low-level child ports combinationally when scheduled code needs live
  observations. Implicit scheduled child-field access can add a register stage.
  `AsynchronousDistributedRamTest` and `CompactCli.MemoryPort` demonstrate explicit wiring.
- Do not depend on zero-filled startup. Write before reading; reset retains
  cells but clears command/validity metadata.
- `InternalRam`, `InternalRam16`, `InternalRam32` and their VHDL files are removed.
  Their byte-enable primitive contract is not part of the replacement. Direct
  users must migrate to full-element writes or provide a separately defined
  masked backend; do not silently replace a masked write with a full write.

For example, the fixed byte specialization can be wired without extra observation
registers as follows (scheduled methods update the command fields):

```livt
process MemoryPort[]()
{
	this.line.address = lineAddress
	this.line.writeEnable = lineWriteEnable
	this.line.writeData = lineWriteData
	lineReadData = this.line.readData
}
```

Dual clocks, true dual ports, byte masks, ECC and initialization files remain
separate capabilities. Do not infer support for them from a storage-style hint.
