# SPI NOR flash

`SPITransactions` adapts the existing asynchronous `SPIMaster` to scheduled,
exclusive `Select`, `Transfer` and `Deselect` calls through `ISPITransactions`.
The physical adapter owns its master; protocol code borrows the adapter. Both
inherit the application context. SPI timing remains expressed as a half-period.
The scheduled wrapper defaults to 100 ns and requires at least five context ticks
per half-period to cover its nested signal-interface round trip. For example,
use 200 ns at 25 MHz, 100 ns at 50 MHz, or 50 ns at 100 MHz. Its constructor
checks this bound. Increase the duration further for slower devices or extra
registered physical adapters.

`SPIFlash<T, CAPACITY, PAGE_SIZE, SECTOR_SIZE, ERASE_COMMAND, TIMEOUT, STYLE, B>` implements
`ISPIFlash` for ordinary single-lane NOR commands with 24-bit addresses.
Defaults are 256-byte pages, 4096-byte sectors, command `0x20`, and a two-second
readiness timeout. These settings must match the actual device; capacity is
required and is limited to 16 MiB. The board owns any configuration-to-user-SPI
handover and restoration of ordinary command mode.

- `ReadJedecId()` reads the manufacturer/type/capacity identity without changing
  protection or mode. Check the expected device before enabling writes.
- `Read(address, length)` loads up to one page into staging; reads may cross pages.
- `SetByte(index, value)` prepares staging for a program operation.
- `ProgramPage(address, length)` programs a page fragment, rejects crossings,
  checks WREN/WEL and waits for WIP to clear. Erase the destination beforehand.
- `EraseSector(address)` requires alignment and erases exactly one sector.
- `GetByte(index)` reads staging; later reads replace its contents.

`STYLE` selects the portable page-buffer backing: `MemoryStyle.Block` (default),
`MemoryStyle.Distributed`, or `MemoryStyle.Auto` for synthesis inference. It is a
synthesis preference, not a latency change or a guarantee of physical placement.
`Auto` does not force registers; the current language has no `MemoryStyle.Registers`.
For example, `SPIFlash<MyTransport, 8388608, 256, 4096, 0x20, 2s, MemoryStyle.Distributed>`
requests distributed staging RAM.

The first valid staging access initializes the
page to zero without SPI traffic; later accesses preserve bytes not overwritten.
This retains the zero-initialized staging contract without a resettable register
array. Reset causes staging to be initialized again on its next use.

All operations have one serialized owner and run in the caller's context.
Readiness polling releases chip select between samples and uses context ticks.
A timeout does not cancel an erase or program already running on the device.
Success means the device became ready; applications must read back data to
confirm writes and detect protection/device-specific failures. The driver does
not clear protection bits or offer chip erase.

Reset clears the controller's state but cannot undo changes to external flash.
Partition boundaries, atomic updates, checksums and recovery belong to storage
services above the driver. `ISPIFlash` permits NOR models and alternative drivers
without binding applications to a vendor.

Run protocol tests with:

```sh
livt test -r SPIFlashTest
```

The optional storage type `B: IRam<byte> & new()` defaults to
`Ram<byte, PAGE_SIZE, STYLE>`. It must provide at least `PAGE_SIZE` bytes and
follow the `IRam` transaction contract. The driver constructs and owns it.
For resettable logic-array backing, use:

```livt
SPIFlash<MyTransport, 8388608, 256, 4096, 0x20, 2s,
    MemoryStyle.Auto, ArrayRam<byte, 256>>
```

An explicit `B` selects the implementation; `STYLE` only affects the default
`Ram` type. Initialization still zeroes staging before first use for every backend.
