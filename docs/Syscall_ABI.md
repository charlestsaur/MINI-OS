# MINI-OS System Call ABI

Applications are trusted Ring 0 code in the kernel's flat address space.

The `int 0x80` interface is an ABI convention, not a privilege or isolation boundary.

Pointer arguments are trusted and are not copied from or validated as user memory.

## Register Convention

- `EAX`: syscall number on entry and return value on return;
- `EBX`, `ECX`, `EDX`: arguments 1, 2, and 3;
- all general-purpose registers other than `EAX` are preserved;
- negative integer returns are errors unless a call documents another form;
- syscall numbers, flags, and common errors are defined once in `transport/lib/syscall.def`.

## Calls

| EAX | Name | EBX | ECX | EDX | Return |
| ---: | --- | --- | --- | --- | --- |
| 1 | `exit` | status (currently ignored) | — | — | Does not return; closes app FDs, resets heap, restores Shell stack |
| 3 | `read` | fd, only 0 | buffer | maximum bytes | line-input byte count; `-2` for bad fd |
| 4 | `write` | fd 1 or 2 | buffer | byte count | count; `-2` for bad fd |
| 5 | `open` | path | open flags | — | fd 3..15 or negative error |
| 6 | `close` | fd | — | — | 0 or `-2` |
| 7 | `getkey` | — | — | — | next supported key/control byte |
| 12 | `brk` | requested break, or 0 to query | — | — | actual break; invalid requests leave it unchanged |
| 14 | `read_file` | fd | buffer | byte count | bytes read, 0 at EOF, or negative error |
| 15 | `write_file` | fd | buffer | byte count | bytes written or negative error |
| 19 | `lseek` | fd | signed offset | `SEEK_SET/CUR/END` | new absolute position or negative error |
| 20 | `move_cursor` | row | column | — | 0; clamps to screen and synchronizes hardware cursor |
| 21 | `clear_screen` | — | — | — | 0 |
| 22 | `set_cursor` | row | column | — | 0; updates logical cursor without immediate hardware sync |
| 23 | `save_screen` | — | — | — | 0; saves 4,000 VGA bytes and cursor position |
| 24 | `restore_screen` | — | — | — | 0; restores saved VGA state and cursor |
| 25 | `get_cursor` | — | — | — | `row * 80 + column` |

`read` blocks until input is available, echoes accepted characters, handles backspace, and does not place the terminating newline in the destination. `getkey` returns the driver's translated Set 1 key value, including the control codes used by `vedit`.

`brk` starts at `0x00180000`, accepts values through the exclusive heap end `0x001C0000`, and resets to the start when an application exits.

## Open Flags and File Descriptors

Flags may be combined subject to these rules:

| Flag | Value | Meaning |
| --- | ---: | --- |
| `SYS_OPEN_READ` | `0x01` | permit reads |
| `SYS_OPEN_WRITE` | `0x02` | permit writes |
| `SYS_OPEN_CREATE` | `0x04` | create when missing |
| `SYS_OPEN_TRUNCATE` | `0x08` | truncate; requires write and conflicts with append |
| `SYS_OPEN_APPEND` | `0x10` | every write starts at current EOF; requires write |

Descriptors 0, 1, and 2 are console input, console output, and console error.

The application file table has 13 slots, numbered 3 through 15, and is cleared on `exit`.

## Common Errors

| Value | Name | Meaning |
| ---: | --- | --- |
| -1 | `SYS_ERR_INVALID` | invalid syscall, argument, flag set, path, or seek origin |
| -2 | `SYS_ERR_BAD_FD` | invalid, closed, or unavailable descriptor |
| -3 | `SYS_ERR_ACCESS` | descriptor mode rejects the operation |
| -4 | `SYS_ERR_IO` | filesystem metadata or ATA operation failed |
| -5 | `SYS_ERR_RANGE` | seek or write would exceed filesystem limits |

The stream functions in `minilibc` translate these calls into `FILE` state.

See `docs/Library_Support.md` for that higher-level contract.
