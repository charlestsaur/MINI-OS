# MINI-OS Filesystem Format Notes

This file explains the implementation choices behind the current format. Exact
numeric values come from `OS_src/kernel/fs/layout.def`; the complete current
contract is documented in `docs/Filesystem_Current.md`.

## Metadata Regions

The image reserves LBA 0 for the boot sector and LBA 1..100 for the kernel.
Filesystem metadata begins at LBA 101:

| Start LBA | Region | Length |
| ---: | --- | ---: |
| 101 | Superblock | 1 sector |
| 102 | Inode bitmap | 1 sector |
| 103 | FAT | 16 sectors |
| 119 | Inode table | 256 sectors |
| 375 | Data blocks | 4,096 sectors |

The inode bitmap and inode table both describe exactly 2,048 inodes. The FAT contains one 16-bit entry for each of the 4,096 data blocks.

## Linked Allocation

Files and directories are not required to occupy contiguous blocks. Allocation selects a free FAT entry, marks it `0xFFFF`, and links it from the previous tail when extending an existing chain. Traversal is bounded by the inode's declared block count and rejects out-of-range values, cycles, early end markers, and a final entry other than `0xFFFF`.

Freeing validates the complete chain before clearing its FAT entries. Directory growth allocates a new cleared block, links it to the previous tail, and then updates the directory inode's block count.

## Directory and Path Model

Directory blocks contain 16 fixed-size entries mapping a name to a child inode.

The child inode repeats its name, type, and parent; mutations keep these fields consistent.

Path resolution starts at root for `/...` and at the current working directory otherwise, then resolves each component through directory entries.

## ATA Interface

Protected-mode storage currently addresses the primary ATA channel's master device with LBA28 PIO. Each one-sector transfer:

1. rejects an address outside LBA28;
2. waits with a fixed bound for BSY to clear;
3. fails on timeout, ERR, or DF;
4. programs sector count, LBA, drive/head, and command;
5. waits for DRQ before transferring 256 words;
6. checks completion status, including cache-flush completion for writes.

The helper returns carry clear on success and carry set on failure.

Filesystem callers translate this into `FS_ERR_IO` and do not continue with invalid data.

## Validation Rule

New format changes must update `layout.def` first and preserve agreement among the kernel, `inject_transport`, `check_image`, the Makefile geometry assertion, and the public documentation. A successful `make test` is required after any metadata or allocation change.
