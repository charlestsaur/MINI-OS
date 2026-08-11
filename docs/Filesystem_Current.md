# MINI-OS Filesystem (Current Implementation)

`OS_src/kernel/fs/layout.def` is the authoritative disk-format definition. The kernel, image builder, injector, and read-only checker all consume it directly. All sectors are 512 bytes.

## Disk Layout

| LBA range | Length | Purpose |
| --- | ---: | --- |
| `0` | 1 | BIOS boot sector |
| `1..100` | 100 | Reserved kernel image |
| `101` | 1 | Superblock |
| `102` | 1 | 2,048-bit inode allocation bitmap |
| `103..118` | 16 | 4,096-entry FAT (`uint16_t` entries) |
| `119..374` | 256 | 2,048 inodes, 64 bytes each |
| `375..4470` | 4,096 | Data blocks |

The complete image is exactly 4,471 sectors, or 2,289,152 bytes.

## Superblock

The first six little-endian 32-bit fields are:

1. magic `0x46415431`;
2. inode count `2048`;
3. data-block count `4096`;
4. inode-table LBA `119`;
5. data-area LBA `375`;
6. root inode index `0`.

## Inode and Directory Entry

An inode is 64 bytes:

- type: `0` free, `1` regular file, `2` directory;
- name: 27-byte NUL-terminated field, allowing at most 26 visible bytes;
- size: regular-file byte length;
- start block: first FAT block index, not an absolute LBA;
- block count: exact FAT-chain length;
- parent: parent inode index;
- reserved: 20 bytes.

A directory entry is 32 bytes: child inode (`uint32_t`), child type (`uint8_t`), and a 27-byte name. One directory block stores 16 entries. Empty entries are all zero.

Names are unique within a directory under the kernel's case-insensitive comparison.

## FAT Contract

Each FAT entry is a little-endian 16-bit value:

- `0`: free block;
- `0xFFFF`: end of chain;
- `2..4095`: next block index.

Entries 0 and 1 are reserved. A data-block index `n` is stored at disk LBA `375 + n`. An allocated inode owns exactly one complete, acyclic chain; no data block may be owned by two inodes. For a nonempty regular file, block count is exactly `ceil(size / 512)`.

Empty files may retain zero blocks or one cleared block after truncation. Directories always own at least one block.

## Mount, Format, and Mutation

At boot the kernel validates the superblock and root inode.

An absent or incompatible format is reformatted; an I/O failure is fatal. Formatting creates root inode 0 on block 2 and `README.TXT` inode 1 on block 3.

Paths may be absolute or relative and support `.` and `..`.

Create, move, remove, file-stream I/O, executable loading, directory growth, and host injection all follow FAT chains with range, length, end-marker, and cycle checks.

Mutations propagate I/O errors and roll back allocations where the operation has not been committed.

The shell's small `edit` command accepts at most 510 bytes and deliberately truncates to one data block.

File syscalls used by `fread` and `fwrite` support multi-block files up to the data-region capacity.

## Integrity Verification and Limits

Every image build runs `build/check_image`. It rejects:

- geometry or superblock mismatches;
- bitmap/inode disagreement;
- invalid, cyclic, short, or overlong FAT chains;
- duplicate block ownership and orphan FAT allocations;
- unreachable inodes, multiple parent links, and directory cycles;
- duplicate directory names or entry/inode disagreement;
- any metadata or data reference outside the image.

The filesystem has no journaling, crash recovery, permissions, ownership, timestamps, format migration, or repair mode. `check_image` is read-only; it reports corruption but does not modify an image.
