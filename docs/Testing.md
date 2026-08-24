# MINI-OS Testing

## Test Targets

```bash
make check-image
make test-e2e
make test-build
make test
```

`make` itself runs the read-only image checker after host injection. `make test` runs both build-policy and QEMU end-to-end regressions.

Tests require Python 3.9 or newer and `qemu-system-i386` in addition to the normal build tools.

## Image Integrity Gate

`tools/check_image.c` verifies the complete image without modifying it:

- boot signature and nonzero per-image identity;
- exact geometry and superblock fields, including a clear mutation marker;
- inode bitmap/type agreement;
- exact, bounded, acyclic FAT chains;
- one owner per allocated data block and no orphan FAT allocation;
- root reachability and exactly one parent link for every other inode;
- NUL-terminated names of at most 26 visible bytes, reserved-name and slash rejection, directory name uniqueness, and entry/inode agreement;
- file-size/block-count agreement without arithmetic wraparound;
- all metadata and data references within image bounds.

Any failure terminates the image build.

## QEMU Filesystem Regression

`tests/qemu_e2e.py` creates a temporary copy of the image and a test-only kernel that mirrors VGA characters to QEMU's debug console. The production kernel and source image are not mutated. The test has explicit timeouts and fails if QEMU hangs or an expected marker is absent.

It boots and asserts:

- Exact string, formatting, heap, BSS, syscall, and stream test results are verified.
- Creation, truncation, exact multi-sector write/read, gap zeroing, and append are verified.
- The 26-byte accepted and 27-byte rejected name boundaries are verified together with trailing-slash and root rejection.
- Two-block ordinary and root directory growth, rename, listing, removal, cleanup, and remount with the root still owning two blocks are verified.
- Current-directory and ancestor removal protection, case-only rename, and current-working-directory refresh after moving an ancestor are verified.
- The `vedit test` screen-rendering path is verified.
- Forced-CHS boots under `5/16/63`, `66/4/17`, and `263/1/17` geometries are verified together with default PC and `isapc` machine types.
- Booting from secondary master while primary master separately mismatches the boot-code sample, image identity, or kernel-code sample is refused in every case, and hashes prove both images remain unchanged.
- An invalid-superblock boot halts without formatting and leaves the image hash unchanged.
- An explicit `format` removes the prior tree, recreates `README.TXT`, passes the checker, and remains mountable after reboot.
- A one-shot ATA write error at FAT LBA 103 disables writes in the current boot, causes the checker to report an unfinished mutation, and makes the next boot refuse the mount.
- A one-shot ATA read error on `README.TXT` refuses later writes in that boot, leaves the image hash unchanged and clean, and permits writes after reboot.
- A nearly full image whose two-block write persists its first block before running out of space retains the unfinished marker and refuses remount even though the terminal error was not an ATA failure.
- Bytes, moves, and removals persist across complete QEMU restarts, including deletion of `README.TXT` and verified reuse of its inode 1.
- Image integrity is verified before remount, after cleanup, and after the final remount.

## Build Regression

`tests/test_build.py` copies the repository to a temporary directory and checks:

- a clean default build and mandatory image verification;
- a binary-level assertion that the kernel image starts with an executable jump whose destination lies inside the image;
- GNU C11 compilation of `transport/lib` and strict C90 flags for apps/tests;
- rejection of a generated C99-only application probe;
- rejection of an unfinished mutation, cyclic FAT, impossible file sizes, and reserved directory names by the image checker;
- rejection of `.`, `..`, and slash-containing injector target names without modifying the image;
- rejection of hard-linked image targets whose aliases could not be atomically replaced together;
- a successful host injection transaction followed by deterministic failure before and after every sector-write and flush stage, with every failed run leaving the original image byte-identical, valid, and free of temporary files;
- deterministic failure of the final permission, flush, close, integrity-check, and rename stages under the same unchanged-original contract;
- safe injector rejection of an unfinished filesystem;
- pre-rename rejection of unrelated corruption that the injection path itself does not traverse, again preserving the original bytes;
- rejection of truncated ELF, invalid section offsets, undefined and duplicate strong symbols, and output overflow by `elf2bin`;
- a no-op incremental build;
- runtime-header and kernel-include dependency rebuilding;
- a clean build with `ld.lld` unavailable, forcing `elf2bin`;
- QEMU BSS smoke boots for both flat-binary producers.

Temporary repositories, images, logs, and debug kernels are removed when the test finishes.

No source timestamps or tracked files in the working tree are changed.
