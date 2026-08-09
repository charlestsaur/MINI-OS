# MINI-OS Build and Run

This document only covers build, image generation, and local execution.

## 1. Prerequisites

Required tools:

- `nasm`
- `cc` for the two modern-C host tools
- `clang` for the freestanding runtime, applications, and tests
- `ld.lld` when available; otherwise the checked `elf2bin` fallback is selected
- `qemu-system-i386`
- shell tools used by `Makefile` (`dd`, `wc`, `mkdir`, `rm`, `grep`, `tr`, `expr`)

## 2. Source and Output Paths

Current source layout:

- bootloader source: `OS_src/boot/boot.asm`
- kernel entry source: `OS_src/kernel/main.asm`

Build outputs:

- `build/boot.bin`
- `build/kernel.bin`
- `build/inject_transport`
- `build/elf2bin`
- `build/mini_os.img`
- `build/transport/apps/*.o`
- `build/transport/lib_test/*.o`
- `transport/build/apps/*.bin`
- `transport/build/lib_test/*.bin`

## 3. Build Commands

From project root:

```bash
make clean
make
```

What happens:

1. Build the modern-C host tools and runtime library.
2. Compile every application and test with strict C90 diagnostics.
3. Link each flat binary with `ld.lld`, or automatically use `elf2bin` when
   `ld.lld` is unavailable.
4. Assemble the kernel and compute its boot-time sector count.
5. Create a raw image of exactly 4,471 sectors, derived from the shared
   `FS_DATA_START_LBA + FS_DATA_BLOCK_COUNT` layout constants.
6. Assert the resulting byte size, write boot/kernel sectors, validate the same
   geometry in the injector, and inject the sorted `transport/` tree.

Host metadata such as `.DS_Store`, `._*`, `Thumbs.db`, and `.git` is excluded.
An image or host-file I/O failure makes the injector and build return nonzero.

To build one application:

```bash
make app APP=hello.c
```

Objects retain their source path below `build/transport/`, so an application
and a library test may safely share a basename.

## 4. Run in QEMU

```bash
make run
```

Equivalent current action:

```bash
qemu-system-i386 -drive file=build/mini_os.img,format=raw,if=ide,index=0,media=disk
```

The explicit IDE index is part of the current driver contract: after the BIOS loads the kernel, protected-mode filesystem I/O addresses the primary ATA channel's master device directly.

## 5. Kernel Size Guard and Boot Reads

The Makefile checks that kernel size does not exceed reserved area (`100` sectors).

If exceeded, build stops with an explicit error.

The boot sector probes EDD and reads those sectors individually with retries; if EDD is unavailable or fails, it retries through a CHS fallback.

Each request uses offset zero and advances the destination segment, including at the 100-sector build limit, so no request crosses a 64 KiB offset boundary.

Application binaries have a separate 64 KiB build-time limit matching the loader image region.

## 6. Dependency Tracking

The kernel target depends on every assembly/layout include below `OS_src/kernel/`. Runtime and application targets depend on all public runtime headers and `syscall.def`.

The Makefile itself is also an input to generated tools, objects, binaries, and the final image, so flag or recipe changes trigger the required rebuild.

## 7. Common Build Issues

### Missing `nasm`

Symptom: assembler command not found.

### Missing `qemu-system-i386`

Symptom: `make run` fails to launch emulator.

### Permission-related issues with tools

Symptom: image write or cleanup commands fail.

## 8. Real Hardware

Physical machine flashing/boot instructions are documented separately in:

- `docs/Real_Hardware_Guide.md`
