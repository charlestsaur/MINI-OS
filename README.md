# MINI-OS

> [!WARNING]
> MINI-OS is only an experimental system and is far from perfect.

Thanks to Gemini, Gork, GPT, and Mistral for their support.

The documentation and some comments were written by GPT. A small part of the code was developed in collaboration with GPT.

Currently, MINI_OS is a very small x86 32-bit pure assembly operating system.

![](/docs/image/OS-demo.png)

(Use QEMU)

## Current Features

- BIOS boot sector loader with kernel load to memory
- Protected-mode kernel entry (`[org 0x8000]`)
- VGA text console and polling keyboard input
- ATA PIO disk I/O (`LBA28`, sector read/write)
- Custom filesystem with persistent directory tree
- Built-in shell commands:
  `help`, `ls`, `pwd`, `cd`, `mkdir`, `touch`, `cat`, `edit`, `rm`, `mv`, `format`

## Project Layout

- `OS_src/boot/`: bootloader sources
- `OS_src/kernel/`: kernel, shell, drivers, filesystem, and utilities
- `docs/`: project documentation
- `build/`: generated binaries and disk image

## Requirements

- `nasm`
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
- `build/mini_os.img`

## Quick Usage in Shell

Typical flow after boot:

```text
mkdir docs
cd docs
touch note.txt
edit note.txt
cat note.txt
mv note.txt note2.txt
ls
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
