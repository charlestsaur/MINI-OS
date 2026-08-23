# MINI-OS Testing

## Test Targets

```bash
make check-image
make test-e2e
make test-build
make test
```

`make` itself runs the read-only image checker after host injection. `make test` runs both build-policy and QEMU end-to-end regressions.

Tests require Python 3 and `qemu-system-i386` in addition to the normal build tools.

## Image Integrity Gate

`tools/check_image.c` verifies the complete image without modifying it:

- exact geometry and superblock fields;
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

1. exact string, formatting, heap, BSS, syscall, and stream test results;
2. creation, truncation, exact multi-sector write/read, gap zeroing, and append;
3. 26/27-byte name boundaries and trailing-slash/root rejection;
4. two-block directory growth, rename, listing, removal, and cleanup;
5. current-directory/ancestor removal protection, case-only rename, and CWD refresh after moving an ancestor;
6. the `vedit test` screen rendering path and a separately built forced-CHS boot;
7. persistence of bytes, moves, and removals across complete QEMU restarts;
8. image integrity before remount, after cleanup, and after the final remount.

## Build Regression

`tests/test_build.py` copies the repository to a temporary directory and checks:

- a clean default build and mandatory image verification;
- GNU C11 compilation of `transport/lib` and strict C90 flags for apps/tests;
- rejection of a generated C99-only application probe;
- rejection of a cyclic FAT, impossible file sizes, and reserved directory names by the image checker;
- rejection of `.`, `..`, and slash-containing injector target names without modifying the image;
- rejection of truncated ELF, invalid section offsets, undefined and duplicate strong symbols, and output overflow by `elf2bin`;
- a no-op incremental build;
- runtime-header and kernel-include dependency rebuilding;
- a clean build with `ld.lld` unavailable, forcing `elf2bin`;
- QEMU BSS smoke boots for both flat-binary producers.

Temporary repositories, images, logs, and debug kernels are removed when the test finishes.

No source timestamps or tracked files in the working tree are changed.
