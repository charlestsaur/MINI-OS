# MINI-OS Architecture Notes

## Layered View

### Layer 0: Bootloader

- File: `OS_src/boot/boot.asm`
- Runs in 16-bit real mode.
- Loads kernel sectors from disk using BIOS.
- Initializes temporary execution environment (segments/stack/GDT).
- Performs protected-mode transition.

### Layer 1: Kernel Core, IDT Syscalls, and Shell

- File: `OS_src/kernel/main.asm`
- Initializes console and IDT interrupt table.
- Ensures file system availability.
- Enters perpetual REPL shell loop.

- File: `OS_src/kernel/idt.asm`
- Manages 256-entry IDT table at physical memory `0x00026000`.
- Implements `int 0x80` system call handler:
  - `EAX=1` (`sys_exit`): restores kernel Shell ESP from `[saved_kernel_esp]` and returns cleanly to Shell.
  - `EAX=3` (`sys_read`): reads keyboard input with character echo, backspace handling, and newline detection into buffer.
  - `EAX=4` (`sys_write`): outputs text buffer to VGA console.
  - `EAX=12` (`sys_brk`): expands process heap break address between `0x00050000` and `0x00080000` for dynamic memory allocation (`malloc`/`free`).
  - `EAX=25`: returns the VGA cursor position as `row * 80 + column`, used by
    application render verification.

- File: `OS_src/kernel/shell.asm`
- Tokenizes command line (`cmd arg1 arg2`).
- Dispatches operations to filesystem wrappers and executable loader (`run`).
- Implements `shell_run`: validates and follows an executable FAT chain, loads
  a maximum 64 KiB image at `0x00040000`, switches the stack to `0x0008F000`,
  and executes it.
- Converts error codes into user-facing messages.

### Layer 2: Drivers

- File: `OS_src/kernel/drivers.asm`
- ATA PIO sector read/write (`LBA28`, sector read/write).
- Keyboard polling and scan-code translation.
- VGA text-mode rendering and cursor control.

### Layer 3: Storage and Utilities

- File: `OS_src/kernel/fs/*.asm`
- Implements metadata lifecycle, path handling, directory mutation, and inode/block allocation.

- File: `OS_src/kernel/utils.asm`
- Shared low-level primitives: zero/copy/string/compare helpers.

- File: `tools/inject_transport.c`
- Host-side C tool that parses MINI-OS filesystem structures and injects the
  host `transport/` tree at `/transport/` during `make`.

## Data Model

### Inode

- Type: `0=free`, `1=file`, `2=directory`
- Name: fixed-size field (`27` bytes)
- Size: file byte count
- Start block: first FAT data-block index
- Blocks count: exact number of blocks in the FAT chain
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

### Executable Run (`run <file>`)

1. Resolve file Inode via path lookup.
2. Verify target is a regular file (`type == 1`).
3. Require a nonzero byte size no greater than 64 KiB and an exact
   `ceil(size / 512)` block count.
4. Validate the complete FAT chain, including range, cycle, and final-EOC
   checks, before changing the application image.
5. Clear `0x00040000..0x0004FFFF`, then follow the FAT chain and read each
   data block into `0x00040000 + i * 512`.
6. Copy bounded argument strings and build `argv` at `0x0008E000`.
7. Save Shell stack pointer in `[saved_kernel_esp]`.
8. Set stack pointer `esp = 0x0008F000` and `call 0x00040000`.
9. On `sys_exit` (`int 0x80`, `eax=1`), `syscall_entry` restores
   `[saved_kernel_esp]` and jumps to `return_to_shell`.

Applications are trusted Ring 0 code in the kernel's flat address space. The
syscall ABI organizes application access to kernel services, but it does not
provide privilege or memory isolation.

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

## Memory Map & Static Buffers

The kernel uses explicit physical memory regions for buffers and execution:

- `0x00007C00`: Bootloader MBR
- `0x00008000`: Kernel code & data (`kernel.bin`)
- `0x00020000`: `BUF_SUPERBLOCK`
- `0x00021000`: `BUF_BITMAP`
- `0x00022000`: `BUF_SECTOR`
- `0x00023000`: `BUF_TEXT`
- `0x00024000`: `BUF_INODE`
- `0x00025000`: `BUF_CMD`
- `0x00026000`: `IDT_BASE` (2048-byte IDT table)
- `0x00040000..0x0004FFFF`: Application image (64 KiB maximum)
- `0x00050000..0x0007FFFF`: Application heap
- `0x0008E000..0x0008E10B`: Argument strings and `argv` pointers
- `0x0008F000`: Application Stack Pointer (grows downwards)
- `0x00090000`: Kernel Stack Pointer (grows downwards)

This avoids dynamic memory management and keeps flows explicit.

## Error Strategy

Most filesystem APIs return integer status codes (`0` success, negative error). The shell maps these to messages.

Representative errors:

- `-1`: not found/exists depending on context
- `-2`: not dir / no inode / not empty depending on API
- `-3`: root deny / invalid move / no data depending on API
- `-4`: invalid path/name or slot exhaustion in selected APIs
