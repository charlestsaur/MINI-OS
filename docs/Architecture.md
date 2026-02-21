# MINI-OS Architecture Notes

## Layered View

### Layer 0: Bootloader

- File: `OS_src/boot/boot.asm`
- Runs in 16-bit real mode.
- Loads kernel sectors from disk using BIOS.
- Initializes temporary execution environment (segments/stack/GDT).
- Performs protected-mode transition.

### Layer 1: Kernel Core and Shell

- File: `OS_src/kernel/main.asm`
- Initializes console.
- Ensures file system availability.
- Enters perpetual REPL shell loop.

- File: `OS_src/kernel/shell.asm`
- Tokenizes command line (`cmd arg1 arg2`).
- Dispatches operations to filesystem wrappers.
- Converts error codes into user-facing messages.

### Layer 2: Drivers

- File: `OS_src/kernel/drivers.asm`
- ATA PIO sector read/write (`LBA28`, one sector).
- Keyboard polling and scan-code translation.
- VGA text-mode rendering and cursor control.

### Layer 3: Storage and Utilities

- File: `OS_src/kernel/fs/*.asm`
- Implements metadata lifecycle, path handling, directory mutation, and inode/block allocation.

- File: `OS_src/kernel/utils.asm`
- Shared low-level primitives: zero/copy/string/compare helpers.

## Data Model

### Inode

- Type: `0=free`, `1=file`, `2=directory`
- Name: fixed-size field (`27` bytes)
- Size: file byte count
- Start block: first LBA in data area
- Blocks count: contiguous data blocks occupied
- Parent: parent inode index

### Directory Entry

- Child inode index
- Child type
- Child name

Directory entries are stored in data blocks referenced by directory inodes.

## Key Control Paths

### Mount/Format

1. Read superblock.
2. Validate magic and key geometry.
3. Validate root inode.
4. If invalid, format disk and bootstrap root + README.

### Path Resolution

1. Choose root/cwd start based on absolute vs relative path.
2. Split path by `/`.
3. Handle `.` and `..`.
4. Resolve each component through directory lookup.

### Rename/Move

1. Split old and new path into `(parent, name)`.
2. Validate destination does not already exist.
3. Reject moving directory into its own subtree.
4. Write destination entry.
5. Clear source entry.
6. Update inode parent + name.

## Memory Buffers (Static)

The kernel uses fixed buffers in low memory for metadata and transient command/text work:

- `BUF_SUPERBLOCK`
- `BUF_BITMAP`
- `BUF_SECTOR`
- `BUF_TEXT`
- `BUF_INODE`
- `BUF_CMD`

This avoids dynamic memory management and keeps flows explicit.

## Error Strategy

Most filesystem APIs return integer status codes (`0` success, negative error). The shell maps these to messages.

Representative errors:

- `-1`: not found/exists depending on context
- `-2`: not dir / no inode / not empty depending on API
- `-3`: root deny / invalid move / no data depending on API
- `-4`: invalid path/name or slot exhaustion in selected APIs
