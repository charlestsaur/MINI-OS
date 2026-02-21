# MINI-OS Code Structure

This document only describes code/file responsibilities.

## 1. Boot Sources

- `OS_src/boot/boot.asm`
  - standard boot path used by current Makefile
  - BIOS disk read
  - GDT setup and protected-mode jump

- `OS_src/boot/real_machine_boot.asm`
  - alternative loader with EDD detection and CHS fallback logic

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
  - handlers (`cat`, `edit`, and command wrappers)

## 4. Driver Layer

- `OS_src/kernel/drivers.asm`
  - ATA PIO read/write helpers (LBA28)
  - keyboard polling and scan-code translation
  - VGA text-mode output/cursor helpers

## 5. Utility Layer

- `OS_src/kernel/utils.asm`
  - memory clear/copy
  - string/name copy
  - case-insensitive compare helpers

## 6. Filesystem Modules

- `OS_src/kernel/fs/bootstrap.asm`: mount/format/bootstrap
- `OS_src/kernel/fs/path.asm`: path resolve/split/validation/cwd path rebuild
- `OS_src/kernel/fs/dir.asm`: directory entry read/write/clear/scan helpers
- `OS_src/kernel/fs/ops.asm`: high-level create/remove/rename logic
- `OS_src/kernel/fs/path_wrappers.asm`: shell-facing path APIs
- `OS_src/kernel/fs/listing.asm`: `ls` rendering
- `OS_src/kernel/fs/alloc.asm`: inode/data allocation, inode read/write, bitmap ops
- `OS_src/kernel/fs.asm`: filesystem include aggregator

## 7. Build Definition

- `Makefile`
  - source path selection
  - build rules for boot/kernel/image
  - run and clean targets
