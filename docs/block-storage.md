# Read-only block storage

`Livt.IO.IReadOnlyBlockDevice` is a transport-independent contract for one retained
block read. It lets application logic consume blocks without depending on the
media transport. The interface itself provides no device driver, filesystem,
partition parser or storage implementation.

## Ownership and timing

The consumer binds a provider in the same clock/reset context and owns its sole
scheduled client. Serialize all calls, including polling and byte access. Multiple
consumers or clock domains require an adapter with explicit arbitration or clock
crossing. A provider may perform transport work independently of consumer polling.

Scheduled calls may take multiple cycles. Acceptance of a read reserves the slot;
it does not mean the media read has completed. The contract does not prescribe a
fixed call latency or transport deadline. Providers document their timing and
failure bounds separately.

## Operations

| Operation | Contract |
|---|---|
| `IsReady()` | Reports media readiness without reserving a read. |
| `GetBlockCount()` | Returns addressable blocks, or zero while unavailable. |
| `GetBlockSize()` | Returns bytes per block, or zero while unavailable. |
| `TryReadBlock(lba)` | Accepts an in-range LBA only while ready and Idle; rejection leaves the slot unchanged. |
| `GetReadState()` | Reports Idle, Active, Complete or Failed without consuming completion. |
| `TryReadByte(index, value)` | Reads an in-range byte of a Complete block without consuming it; failure returns false and zero. |
| `CancelRead()` | Requests cancellation of an active read; the consumer still waits for completion. |
| `ReleaseRead()` | Releases Complete or Failed back to Idle; returns false while Idle or Active. |

## Retained read lifecycle

1. Wait for readiness and inspect the block count and block size.
2. Submit an LBA smaller than the reported block count with `TryReadBlock()`.
   Readiness and geometry are snapshots; check acceptance even after checking them.
3. An accepted read enters Active. Poll until Complete or Failed.
4. On Complete, read indices from zero through block size minus one. Check each
   `TryReadByte()` result because media loss can invalidate bytes between calls.
5. Call `ReleaseRead()` after consuming the block or observing failure. The next
   read cannot be accepted until the retained slot is released.

Complete data remains available under consumer backpressure. Reading a byte does
not advance an internal cursor or release the block. Failed or incomplete reads
never expose a successful payload prefix through this interface.

## Cancellation, media loss and reset

`CancelRead()` requests cancellation; it does not release the slot. Wait until the
provider stops the operation and exposes Failed, then release it. Providers must
not reuse storage while an active transport still owns it.

Media loss invalidates retained bytes and makes geometry unavailable. A consumer
must handle failed reads even when an earlier readiness check succeeded. Context
reset cancels scheduled work and discards ownership; no completion is promised
across reset. The consumer restarts its readiness and read sequence afterward.
Reset need not erase the provider's payload RAM: validity and ownership prevent
uninitialized or stale bytes from becoming visible.

## Geometry and storage choices

The interface does not assume 512-byte blocks. Consumers use the provider's block
size and reject unsupported geometry before interpreting data. An LBA is a block
index, not a byte offset; address arithmetic must respect the reported capacity.

Providers choose buffering and expose storage configuration through their own
generics where supported. A BRAM-backed provider and a register-array provider can
implement the same contract with different resource costs and scheduled latency.
Those choices must preserve acceptance, completion, retention and reset behavior.
