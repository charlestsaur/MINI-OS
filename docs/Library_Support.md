# MINI-OS Runtime Library Support

`transport/lib/minilibc.c` is a modern-C implementation of a deliberately limited application runtime. Applications under `transport/apps/` and `transport/lib_test/` consume its headers while compiling as strict C90. Header names resemble standard C headers, but this is not a complete ANSI C90 library.

## Tested Function Matrix

| Area | Implemented and tested | Important limits |
| --- | --- | --- |
| Console I/O | `read`, `write`, `getchar`, `putchar`, `gets`, `fgets`, `puts` | polling input; `gets` has no bound and should be avoided for untrusted input; only console fds 0/1/2 |
| Formatting | `printf`, `sprintf`, `snprintf` | `%c`, `%s`, `%d`, `%i`, `%u`, `%x`, `%p`, `%%`; optional `l` for integer conversions; no flags, width, precision, octal, or floating point |
| File streams | `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `ftell`, `rewind`, `fflush`, `feof`, `ferror` | modes `r/w/a`, optional `+` and ignored `b`; unbuffered; 13 simultaneous app file descriptors; no `clearerr`, `remove`, `rename`, or temporary-file APIs |
| Memory/string | `memset`, `memcpy`, `memmove`, `memcmp`, `memchr`, `strlen`, `strcpy`, `strncpy`, `strcat`, `strncat`, `strcmp`, `strncmp`, `strchr`, `strrchr`, `strstr`, `strtok` | caller supplies valid pointers and capacities; `strtok` uses one global saved position |
| Character classification | `isalpha`, `isdigit`, `isalnum`, `isspace`, `islower`, `isupper`, `isprint`, `isgraph`, `ispunct`, `isxdigit`, `iscntrl`, `toupper`, `tolower` | ASCII behavior only; no locale |
| Allocation | `malloc`, `free`, `calloc`, `realloc` | fixed heap `0x50000..0x80000`; no invalid-pointer detection, concurrency, or process isolation |
| Conversion/math helpers | `atoi`, `strtol`, `strtoul`, `abs`, `labs` | no `errno`; integer overflow is not diagnosed; `strtoul` shares the signed parser implementation |
| Algorithms/random | `qsort`, `bsearch`, `rand`, `srand` | `qsort` is a simple quadratic implementation; `bsearch` requires sorted input; deterministic non-cryptographic generator |
| Definitions | `size_t`, `ptrdiff_t`, `offsetof`, `NULL`, integer limits, `assert` | project ABI is 32-bit; `assert` terminates through the runtime |
| Screen helpers | `move_cursor`, `set_cursor`, `clear_screen`, `save_screen`, `restore_screen`, `get_cursor_position` | MINI-OS extensions, not standard C APIs |

## Formatting Behavior

`snprintf` returns the number of characters that would have been emitted, NUL-terminates when size is nonzero, and accepts `NULL` only when size is zero. An unsupported conversion is emitted literally, such as `%q`. A trailing `%` is also emitted literally. There is no field padding, precision, sign/alternate format flag, uppercase hexadecimal, octal, or floating-point conversion.

`printf` and `puts` write directly to VGA through syscalls. File streams are also unbuffered, so `fflush` validates the stream and otherwise has nothing to commit.

## Stream State

- a short read at file end sets EOF without setting the error flag;
- mode violations, multiplication overflow, invalid seek, and syscall failure set the stream error flag;
- a successful seek or rewind clears EOF;
- append mode ignores the current seek position for writes;
- seeking beyond EOF is allowed, and a later write zero-fills the gap through the filesystem's cleared-block behavior;
- file size is limited by the 4,096-block data region.

Executable tests in `transport/lib_test/` compare exact strings, bytes, return values, stream flags, allocation behavior, BSS state, and multi-block file contents. Their success markers are asserted by `make test` in QEMU.
