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
- No journal, automatic rollback/replay, or crash repair exists, although a persistent marker detects an interrupted mutation and forces a read-only halt instead of silently mounting the ambiguous result.
- No standalone fsck/repair command.
- No file permissions model.
- No ownership metadata.
- No timestamp metadata.
- On-disk compatibility/version migration is not defined.

## Device And Driver Layer

- ATA PIO path is polling-based.
- Protected-mode storage supports only an LBA28 disk exposed as the primary ATA channel's master device, and the BIOS boot-drive number is not mapped to a kernel storage device.
- The kernel refuses a target whose boot-code prefix, 48-bit image identity, or kernel-code sample differs from the BIOS-loaded image.
- Images sharing all checked bytes, including clones whose filesystems later diverge, remain indistinguishable, and a 48-bit identity can theoretically collide.
- Disk I/O reports success/failure after bounded waits and `ERR`/`DF` checks, but does not expose richer controller diagnostics to shell-level logic.
- Keyboard input is polling-based and uses a limited Set 1 US-layout mapping; there is no Caps Lock, alternate layout, or asynchronous input state.

## Robustness And Validation

- Runtime guards validate the structures needed by each operation, and every generated image is fully walked by the host-side read-only checker.
- Kernel mutations are fail-stop rather than atomic because a failure after a persistent operation write may leave partial changes, while the persistent marker blocks further writes and remount.
- Any ATA I/O failure disables later filesystem writes for that boot.
- There is no in-system repair utility.
- A dirty image cannot reach the shell's `format` command, and the injector refuses it, so recovery currently means offline inspection or replacing or rebuilding the image.

## Testing And Tooling

- Automated QEMU tests cover library assertions, multi-block file I/O, append/move/remove behavior, persistence, deterministic ATA read/write faults, partial-write exhaustion, wrong-device refusal, three forced-CHS geometries, default PC, and `isapc`.
- Automated build tests cover the language-policy split, relevant dependency rebuilds, no-op builds, both flat-binary link paths, dirty-image rejection, every host-injector sector-write failure point before and after flush, and every final transaction stage including the full pre-rename integrity gate.
- Physical-machine compatibility remains unverified because firmware USB-to-legacy-ATA mapping varies and cannot be established by emulator coverage.

## Summary

The system is functional for its current personal-project scope, but reliability and fault tolerance remain limited.

Using it as an experimental environment is reasonable; using it as a trusted storage system is not.
