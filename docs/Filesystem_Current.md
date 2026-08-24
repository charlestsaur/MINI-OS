# MINI-OS Filesystem (Current Implementation)

`OS_src/kernel/fs/layout.def` is the authoritative disk-format definition. The kernel, image builder, injector, and read-only checker all consume it directly. All sectors are 512 bytes.

## Disk Layout

| LBA range | Length | Purpose |
| --- | ---: | --- |
| `0` | 1 | BIOS boot sector, including the image identity at bytes `504..509` |
| `1..100` | 100 | Reserved kernel image |
| `101` | 1 | Superblock |
| `102` | 1 | 2,048-bit inode allocation bitmap |
| `103..118` | 16 | 4,096-entry FAT (`uint16_t` entries) |
| `119..374` | 256 | 2,048 inodes, 64 bytes each |
| `375..4470` | 4,096 | Data blocks |

The complete image is exactly 4,471 sectors, or 2,289,152 bytes.

## Superblock

The first seven little-endian 32-bit fields are:

- magic `0x46415431`;
- inode count `2048`;
- data-block count `4096`;
- inode-table LBA `119`;
- data-area LBA `375`;
- root inode index `0`;
- unfinished-mutation marker: `0` for clean, `1` while a persistent mutation is active.

The image builder also places a nonzero 48-bit random image identity in boot sector bytes `504..509`.

It is not filesystem metadata, but the kernel uses it as part of the storage-target safety check.

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

Before reading filesystem metadata, the kernel verifies that primary-master ATA LBA 0 has the immutable boot-code prefix and image identity currently executing at `0x7C00`.

It also compares an immutable kernel-code sample.

A mismatch halts without writing either disk.

This normally distinguishes separately generated images.

Images sharing every checked identity/code byte, including clones whose filesystem contents later diverge, remain indistinguishable, and independent 48-bit identities have a small theoretical collision probability.

The kernel then validates the superblock, requires a clear unfinished-mutation marker, and validates the root inode and its complete FAT chain.

Any failure in these startup checks stops boot without formatting.

Other structures are validated as operations traverse them, while every generated image is fully walked by the host checker.

The explicit shell `format` command is available only after a clean filesystem has mounted.

It creates root inode 0 on block 2 and `README.TXT` inode 1 on block 3.

Only inode 0 is permanently reserved, so removing `README.TXT` makes inode 1 allocatable again.

The root directory may grow to a multi-block FAT chain and remains mountable in that form.

Paths may be absolute or relative and support `.` and `..`.

Create, move, remove, file-stream I/O, executable loading, directory growth, and host injection all follow FAT chains with range, length, end-marker, and cycle checks.

Every kernel mutation first persists marker value `1`.

After all operation writes and required rollback writes succeed, it persists marker value `0`.

A validation or semantic error that occurs before any operation write may also clear the marker safely.

Once an operation write has succeeded, however, any later error leaves the marker set rather than assuming rollback was complete.

Any ATA read or write failure disables further filesystem writes for the current boot.

If a mutation is active, its marker remains set.

A later boot and `check_image` both refuse an image whose marker is still set.

This is a fail-stop consistency contract rather than an atomic rollback promise.

Data and metadata may be partially changed after the reported I/O failure.

The marker prevents that ambiguous state from being silently mounted or extended, but the current implementation has no repair path, so recovery requires inspecting or replacing the image.

Host injection uses a different transaction boundary.

`inject_transport` copies the image to a uniquely named file in the same directory, performs and flushes all changes there, closes it, runs the complete read-only integrity checker on that copy, and then atomically renames it over the target.

Any injection, write, flush, close, integrity-check, or rename failure leaves the original image byte-for-byte unchanged.

The tool removes the temporary copy when the host filesystem permits it and reports a cleanup failure otherwise.

It formats only a zeroed fresh superblock and rejects a nonzero invalid or unfinished superblock.

An abrupt process or host termination can leave an uncommitted `.inject-*` sidecar for manual cleanup, but the target path is not replaced before the commit rename.

The shell's small `edit` command accepts at most 510 bytes and deliberately truncates to one data block.

File syscalls used by `fread` and `fwrite` support multi-block files up to the data-region capacity.

## Integrity Verification and Limits

Every image build runs `build/check_image`. It rejects:

- boot signature/identity, geometry, or superblock mismatches;
- an unfinished-mutation marker;
- bitmap/inode disagreement;
- invalid, cyclic, short, or overlong FAT chains;
- duplicate block ownership and orphan FAT allocations;
- unreachable inodes, multiple parent links, and directory cycles;
- duplicate directory names or entry/inode disagreement;
- any metadata or data reference outside the image.

The filesystem has no journal, automatic rollback/replay, permissions, ownership, timestamps, format migration, or repair mode.

`check_image` is read-only, so it reports corruption or an unfinished mutation without modifying an image.
