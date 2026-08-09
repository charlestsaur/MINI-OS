# MINI-OS Limitations

This file documents current limitations only.

## Platform And Runtime

- Single-task execution model (executes raw flat binaries loaded at `0x00040000`).
- System calls via `int 0x80` (`sys_exit`, `sys_read`, `sys_write`, `sys_brk`) implemented via IDT interrupt gates.
- Dynamic heap memory allocation (`malloc`, `free`, `realloc`, `calloc`) managed by `sys_brk` (heap space `0x00050000` to `0x00080000`).
- Full ANSI C90 standard library support (`<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<ctype.h>`, `<limits.h>`, `<stddef.h>`, `<assert.h>`).
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

- Consistency checks are limited to mount-time structure validation and selected runtime guards.
- Corrupted metadata outside currently checked paths may still cause undefined behavior.
- Recovery workflow after corruption is mostly reformat-centric.

## Testing And Tooling

- No automated end-to-end command regression suite.
- Build dependencies are simple and do not track full include graph changes.
- No formal compatibility test matrix for different emulators or hardware variants.

## Summary

The system is functional for its current personal-project scope, but reliability and fault tolerance remain limited.

Using it as an experimental environment is reasonable; using it as a trusted storage system is not.
