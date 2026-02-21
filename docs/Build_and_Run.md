# MINI-OS Build and Run

This document only covers build, image generation, and local execution.

## 1. Prerequisites

Required tools:

- `nasm`
- `qemu-system-i386`
- shell tools used by `Makefile` (`dd`, `wc`, `mkdir`, `rm`)

## 2. Source and Output Paths

Current source layout:

- bootloader source: `OS_src/boot/boot.asm`
- kernel entry source: `OS_src/kernel/main.asm`

Build outputs:

- `build/boot.bin`
- `build/kernel.bin`
- `build/mini_os.img`

## 3. Build Commands

From project root:

```bash
make clean
make
```

What happens:

1. Assemble kernel binary.
2. Compute kernel sector count.
3. Assemble boot binary with `KERNEL_SECTORS` define.
4. Create raw disk image (`4096` sectors).
5. Write boot sector to LBA 0.
6. Write kernel binary starting at LBA 1.

## 4. Run in QEMU

```bash
make run
```

Equivalent current action:

```bash
qemu-system-i386 -drive format=raw,file=build/mini_os.img
```

## 5. Kernel Size Guard

The Makefile checks that kernel size does not exceed reserved area (`100` sectors).
If exceeded, build stops with an explicit error.

## 6. Common Build Issues

### Missing `nasm`

Symptom: assembler command not found.

### Missing `qemu-system-i386`

Symptom: `make run` fails to launch emulator.

### Permission-related issues with tools

Symptom: image write or cleanup commands fail.

## 7. Real Hardware

Physical machine flashing/boot instructions are documented separately in:

- `docs/Real_Hardware_Guide.md`
