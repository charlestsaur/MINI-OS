# MINI-OS Code Structure

This document only describes code/file responsibilities.

## 1. Boot Sources

- `OS_src/boot/boot.asm`
  - EDD detection, bounded one-sector reads, retries, disk resets, and CHS fallback
  - conventional and extended physical-memory checks before the kernel is loaded or protected-mode fixed regions are used
  - fast A20 enablement and physical alias verification before protected mode
  - fixed location for the host-generated per-image boot identity
  - GDT setup and protected-mode jump

## 2. Kernel Entry and Global Constants

- `OS_src/kernel/main.asm`
  - kernel image origin (`[org 0x8000]`) and first-byte jump to `kernel_start`
  - complete kernel-stack clearing and lower-canary initialization before the first call
  - global constants (VGA, ATA, filesystem layout) and compile-time platform-layout assertions
  - global state buffers and scratch variables
  - includes shell/fs/driver/utility modules
- `OS_src/kernel/platform_layout.def`
  - shared boot, kernel, work-buffer, network-buffer, application-image, heap, argument, stack, canary, configured-memory, and firmware-required-memory constants

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
  - fixed-buffer initialization, application-memory initialization, interrupt-stack boundary exercise, and shared canary verification

## 7. Filesystem Modules

- `OS_src/kernel/fs/bootstrap.asm`: storage-target verification, clean mount, explicit format, and persistent mutation-marker lifecycle
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
  - assigns the per-image boot identity and validates image geometry/FAT chains
  - mutates a same-directory temporary copy and atomically replaces the target only after flush, close, and the full image-integrity gate succeed
- `tools/check_image.c` / `tools/check_image.h`
  - reusable read-only boot-identity, mutation-marker, geometry, inode, directory, FAT-chain, reachability, and allocation-ownership verifier
  - command-line checker and the injector's pre-rename commit gate share the same implementation
- `tools/elf2bin.c`
  - host C 32-bit ELF linker and flat binary generator with checked output, object, global-symbol, per-object-section, and relocation capacities
- `tools/check_layout.c`
  - host C verifier for platform-memory consistency, bounds, alignment, containment, adjacency, and pairwise non-overlap
- `transport/lib/`
  - `crt0.asm`: C runtime startup file (`_start`)
  - `minilibc.h` / `minilibc.c`: modern-C runtime implementation and heap allocator
  - `compiler_rt.c`: modern-C unsigned 64-bit division and remainder helpers linked only where required
  - `net/`: modern-C network implementation directory
  - `ssh/`: modern-C SSH implementation directory
  - `stdio.h`, `stdlib.h`, `string.h`, `ctype.h`, `limits.h`, `stddef.h`, `assert.h`: standard C header wrappers
- `transport/app.ld`
  - shared high-memory application section placement and complete allocatable-image assertion for the `ld.lld` path
- `transport/apps/`
  - strict C90 application sources (`hello.c`, `calc.c`, `guess.c`, `banner.c`, `vedit.c`)
- `transport/lib_test/`
  - strict C90 executable assertions in `test_string.c`, `test_heap.c`, `test_file.c`, `test_no_space.c`, `test_bss.c`, `test_stack.c`, and the isolated fail-stop probe `test_guard.c`
- `transport/build/`
  - compiled flat binary outputs (`apps/*.bin`, `lib_test/*.bin`)

## 9. Build Definition

- `Makefile`
  - source path selection
  - build rules for boot/kernel/image/tool/apps
  - strict-C90 application and modern-C library policies with per-application network and SSH object selection
  - shared layout-derived linker, loader-capacity, kernel-reservation, and QEMU-memory values
  - mandatory final-image integrity check
  - normal and network QEMU run targets plus test and clean targets

## 10. Automated Test Drivers

- `tests/qemu_e2e.py`
  - boots temporary debug images, checks insufficient-memory and A20 failures, proves every canary-corruption fail-stop branch, checks the network launch configuration, drives the shell, asserts application guards and multi-block filesystem behavior, restarts and checks persistent state, injects ATA faults, verifies wrong-device refusal, and exercises the supported QEMU machine/CHS matrix
- `tests/test_build.py`
  - checks clean and incremental builds, C language policy, per-application dependencies, layout assertions, parameterized linker limits, both exact-limit flat-binary paths, checker rejection, and every before/after sector-write failure point in the host injector transaction
