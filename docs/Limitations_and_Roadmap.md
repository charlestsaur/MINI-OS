# MINI-OS Limitations

This file documents current limitations only.

## Platform And Runtime

- Single-task execution model (executes raw flat binaries loaded at `0x00040000`).
- System calls via `int 0x80` for console, heap, file, and cursor services; `Syscall_ABI.md` documents all implemented calls and their register contract.
- Dynamic heap memory allocation (`malloc`, `free`, `realloc`, `calloc`) managed by `sys_brk` (heap space `0x00050000` to `0x00080000`).
- A tested runtime subset exposed through familiar C headers; unsupported functions and reduced contracts are listed in `Library_Support.md`.
- No Ring 3 hardware process isolation; user applications and kernel share Ring 0 flat protected mode.
- No virtual memory or paging.
- No interrupt-driven scheduling.

## Filesystem And Storage

- FAT-chain allocation; files may be fragmented across the data region.
- No journaling and no crash recovery.
- No standalone fsck/repair command.
- No file permissions model.
- No ownership metadata.
- No timestamp metadata.
- On-disk compatibility/version migration is not defined.

## Device And Driver Layer

- ATA PIO path is polling-based.
- Protected-mode storage supports only an LBA28 disk exposed as the primary ATA channel's master device; the BIOS boot-drive number is not yet mapped to a kernel storage device.
- Disk I/O reports success/failure after bounded waits and `ERR`/`DF` checks, but does not expose richer controller diagnostics to shell-level logic.
- Keyboard input is polling-based and uses a limited Set 1 US-layout mapping; there is no Caps Lock, alternate layout, or asynchronous input state.

## Robustness And Validation

- Runtime guards validate the structures needed by each operation, and every generated image is fully walked by the host-side read-only checker.
- There is no in-system repair utility; recovery after corruption remains reformat- or host-tool-centric.

## Testing And Tooling

- Automated QEMU tests cover library assertions, multi-block file I/O, append/move/remove behavior, persistence across reboot, and final metadata integrity.
- Automated build tests cover the language-policy split, relevant dependency rebuilds, no-op builds, and both flat-binary link paths.
- No formal compatibility test matrix for different emulators or hardware variants.

## Summary

The system is functional for its current personal-project scope, but reliability and fault tolerance remain limited.

Using it as an experimental environment is reasonable; using it as a trusted storage system is not.
