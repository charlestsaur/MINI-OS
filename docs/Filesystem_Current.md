# MINI-OS Filesystem (Current Implementation)

This document describes the filesystem as it works today in the current codebase.

## 1. Disk Layout

All values are sector-based (`512` bytes per sector):

- `LBA 0`: boot sector
- `LBA 1..100`: reserved kernel image area
- `LBA 101`: superblock
- `LBA 102`: inode bitmap (`1` sector)
- `LBA 103..110`: data bitmap (`8` sectors)
- `LBA 111..366`: inode table (`256` sectors)
- `LBA 367+`: data blocks

Main constants are defined in `OS_src/kernel/main.asm`.

## 2. Core Structures

### Superblock

Fields currently used:

- magic number (`FS_MAGIC`)
- inode count
- data block count
- inode table start LBA
- data start LBA
- root inode index

### Inode (`64` bytes)

- type (`0` free, `1` file, `2` directory)
- name (fixed-length `27` bytes)
- size (bytes)
- start LBA (first data block)
- block count
- parent inode index

### Directory Entry (`32` bytes)

- child inode index (`4` bytes)
- child type (`1` byte)
- child name (`27` bytes)

Each directory data block stores `16` directory entries.

## 3. Mount And Format Behavior

On boot:

1. The kernel reads and validates the superblock.
2. It validates root inode shape and bounds.
3. If validation fails, it formats the filesystem.

Format currently creates:

- root directory inode (`inode 0`)
- `README.TXT` inode (`inode 1`)
- one root directory entry pointing to `README.TXT`
- README text content in its data block

Implementation: `OS_src/kernel/fs/bootstrap.asm`.

## 4. Path Handling

Supported path behavior:

- absolute paths (`/a/b`)
- relative paths (`a/b`)
- `.` and `..`

Path resolution walks directory entries step-by-step from either root or current working directory.

Implementation: `OS_src/kernel/fs/path.asm`.

## 5. File And Directory Operations

Current high-level operations include:

- create file
- create directory
- remove file or empty directory
- rename/move across directories

Important safeguards currently present:

- invalid names are rejected (`"."`, `".."`, empty, too long)
- directory metadata bounds are checked before scans
- rename blocks moving a directory into itself/subtree
- inode index bounds checks in inode read/write helpers
- data-block free checks include lower and upper bounds

Implementations:

- `OS_src/kernel/fs/ops.asm`
- `OS_src/kernel/fs/dir.asm`
- `OS_src/kernel/fs/alloc.asm`

## 6. Text File Editing Model

`edit <file>` currently:

1. Resolves or creates the file.
2. Reads keyboard input until `ESC`.
3. Stores content in one sector buffer.
4. Allocates one data block if needed.
5. Writes content and updates inode size.

This means current text save behavior is effectively limited to one sector payload per file write path.

Implementation: `OS_src/kernel/shell.asm`.

## 7. Error Code Conventions

Most filesystem routines return `0` for success and negative values for failure.

Exact meanings vary by API, for example:

- `-1`: not found or already exists (context dependent)
- `-2`: type/empty-state related failure (context dependent)
- `-3`: denied/invalid move/no data (context dependent)
- `-4`: invalid path/name or slot/allocation-related failure (context dependent)

## 8. Practical Constraints In Current FS

- contiguous allocation model only
- no journaling
- no crash recovery
- no permissions
- no timestamps
- no standalone fsck/repair tool

For a broader project-level list, see `docs/Limitations_and_Roadmap.md`.
