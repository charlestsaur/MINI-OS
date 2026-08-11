# MINI-OS Code Structure

This document only describes code/file responsibilities.

## 1. Boot Sources

- `OS_src/boot/boot.asm`
  - EDD detection, bounded one-sector reads, retries, disk resets, and CHS fallback
  - GDT setup and protected-mode jump

## 2. Kernel Entry and Global Constants

- `OS_src/kernel/main.asm`
  - kernel entry point (`[org 0x8000]`)
  - global constants (VGA, ATA, filesystem layout)
  - global state buffers and scratch variables
  - includes shell/fs/driver/utility modules

## 3. Shell Layer

- `OS_src/kernel/shell.asm`
  - command parser
  - command dispatch
  - user-facing error message mapping
  - handlers (`cat`, `edit`, `run`, and command wrappers)
  - `shell_run`: multi-sector executable loader and runner

## 4. Interrupts & System Calls

- `OS_src/kernel/idt.asm`
  - IDT table setup (`lidt`)
  - `int 0x80` system call gate handler for calls 1, 3--7, 12, 14, 15, and 19--25; see `docs/Syscall_ABI.md` for the complete contract

## 5. Driver Layer

- `OS_src/kernel/drivers.asm`
  - checked primary-master ATA PIO read/write helpers (LBA28)
  - polling Set 1 / US-layout keyboard translation
  - VGA text-mode output/cursor helpers, including row-crossing backspace

## 6. Utility Layer

- `OS_src/kernel/utils.asm`
  - memory clear/copy
  - string/name copy
  - case-insensitive compare helpers

## 7. Filesystem Modules

- `OS_src/kernel/fs/bootstrap.asm`: mount/format/bootstrap
- `OS_src/kernel/fs/path.asm`: path resolve/split/validation/cwd path rebuild
- `OS_src/kernel/fs/dir.asm`: directory entry read/write/clear/scan helpers
- `OS_src/kernel/fs/ops.asm`: high-level create/remove/rename logic
- `OS_src/kernel/fs/path_wrappers.asm`: shell-facing path APIs
- `OS_src/kernel/fs/listing.asm`: `ls` rendering
- `OS_src/kernel/fs/alloc.asm`: inode/FAT-block allocation, inode read/write, inode-bitmap and FAT operations
- `OS_src/kernel/fs.asm`: filesystem include aggregator

## 8. Host Tools & User Applications

- `tools/inject_transport.c`
  - checked host C program for deterministic injection of the `transport/` tree at `/transport/`
  - validates image geometry and FAT chains and propagates mutation failures
- `tools/elf2bin.c`
  - host C 32-bit ELF linker and flat binary generator
- `tools/check_image.c`
  - read-only image geometry, inode, directory, FAT-chain, reachability, and allocation-ownership verifier
- `transport/lib/`
  - `crt0.asm`: C runtime startup file (`_start`)
  - `minilibc.h` / `minilibc.c`: modern-C runtime implementation and heap allocator
  - `stdio.h`, `stdlib.h`, `string.h`, `ctype.h`, `limits.h`, `stddef.h`, `assert.h`: standard C header wrappers
- `transport/apps/`
  - strict C90 application sources (`hello.c`, `calc.c`, `guess.c`, `banner.c`, `vedit.c`)
- `transport/lib_test/`
  - strict C90 executable assertions in `test_string.c`, `test_heap.c`, `test_file.c`, and `test_bss.c`
- `transport/build/`
  - compiled flat binary outputs (`apps/*.bin`, `lib_test/*.bin`)

## 9. Build Definition

- `Makefile`
  - source path selection
  - build rules for boot/kernel/image/tool/apps
  - mandatory final-image integrity check
  - run, test, and clean targets

## 10. Automated Test Drivers

- `tests/qemu_e2e.py`
  - boots a temporary debug image, drives the shell, asserts application and multi-block filesystem behavior, restarts the same image, and checks it
- `tests/test_build.py`
  - checks clean and incremental builds, C language policy, dependency edges, checker rejection, and both flat-binary link paths
