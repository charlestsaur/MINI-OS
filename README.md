# MINI-OS

Currently, MINI-OS is a very small x86 32-bit pure assembly operating system.

MINI-OS supports running ANSI C90 C programs with dynamic memory allocation (malloc/free) and standard library support, excluding floating-point operations (float/double).

> [!NOTE]
> MINI-OS is only an experimental system and is far from perfect.

Thanks to Gemini, Gork, GPT, and Mistral for their support.

The documentation and some comments were written by Gemini and GPT. A small part of the code was developed in collaboration with Gemini and GPT.

![](/docs/image/OS-demo.png)

(Use QEMU)

👉 [Flowchart](docs/Flowchart.md)

## Current Features

- BIOS boot sector loader with kernel load to memory
- Protected-mode kernel entry (`[org 0x8000]`)
- VGA text console and polling keyboard input
- ATA PIO disk I/O (`LBA28`, sector read/write)
- Custom filesystem with persistent directory tree
- IDT Interrupt Table & `int 0x80` System Call Engine (`sys_exit`, `sys_read`, `sys_write`, `sys_brk`)
- Executable loader (`run <file>`) for multi-sector flat binaries at `0x00040000`
- C90 application runtime with **Dynamic Memory Allocation (`malloc`/`free`/`realloc`/`calloc`)**
- ANSI C90 standard headers (`<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<ctype.h>`, `<limits.h>`, `<stddef.h>`, `<assert.h>`)
- Host-side disk transport tool (`tools/inject_transport.c`) for inject `/transport/` files
- Built-in shell commands:
  `help`, `ls`, `pwd`, `cd`, `mkdir`, `touch`, `cat`, `edit`, `rm`, `mv`, `run <file>`, `format`

## Project Layout

- `OS_src/boot/`: bootloader sources
- `OS_src/kernel/`: kernel, shell, drivers, filesystem, IDT & syscalls, and utilities
- `tools/`: host build tools (`inject_transport.c`, `elf2bin.c`)
- `transport/`: host files injected into `/transport/` on disk image
  - `transport/lib/`: C90 runtime library, `crt0.asm`, and standard C header wrappers
  - `transport/apps/`: user C applications (`hello.c`, `calc.c`, `guess.c`, `banner.c`)
  - `transport/lib_test/`: dedicated C library test suites (`test_string.c`, `test_heap.c`)
  - `transport/build/`: compiled flat output binaries (`apps/*.bin`, `lib_test/*.bin`)
- `docs/`: project documentation
- `build/`: generated kernel binaries and disk image

## Requirements

- `nasm`
- `cc` / `clang` / `gcc` (host C compiler for `inject_transport` build)
- `qemu-system-i386`
- standard shell tools used by `Makefile` (`dd`, `wc`, `mkdir`, `rm`)

## Build and Run

```bash
make clean
make
make run
```

Build artifacts:

- `build/boot.bin`
- `build/kernel.bin`
- `build/inject_transport`
- `build/mini_os.img`

## Quick Usage in Shell

Typical flow after boot:

```text
mkdir docs
cd /docs
touch note.txt
edit note.txt
cat note.txt
mv note.txt note2.txt
ls

cd /transport/build
ls
run hello.bin
run calc.bin

```

## Filesystem Snapshot

Sector layout in current implementation:

- `LBA 0`: boot sector
- `LBA 1..100`: reserved kernel area
- `LBA 101`: superblock
- `LBA 102`: inode bitmap
- `LBA 103..110`: data bitmap
- `LBA 111..366`: inode table
- `LBA 367+`: data blocks

## Documentation Index

- Project overview: `docs/Project_Overview.md`
- Architecture: `docs/Architecture.md`
- Code structure: `docs/Code_Structure.md`
- Build and run: `docs/Build_and_Run.md`
- Shell and usage: `docs/Shell_and_Usage.md`
- C90 development guide: `docs/C90_Development_Guide.md`
- Filesystem (current implementation): `docs/Filesystem_Current.md`
- Filesystem design draft: `docs/DIY-FS.md`
- Real hardware boot guide: `docs/Real_Hardware_Guide.md`
- Known limitations: `docs/Limitations_and_Roadmap.md`

## Real Hardware Note

> [!CAUTION]
> MINI-OS uses a very primitive file system implementation and has known flaws (such as aggressive, brute-force disk read/write operations). Therefore, long-term use may increase hardware wear and tear.
>
> Apart from this, MINI-OS does not perform any destructive operations on the machine. Nevertheless, to prevent potential data loss or hardware damage, it is still recommended to run it on a non-critical machine.

This project currently targets BIOS/CSM-style boot flows.

For USB boot on physical machines, read `docs/Real_Hardware_Guide.md` carefully.

Writing images to raw devices can destroy existing data on that device.
