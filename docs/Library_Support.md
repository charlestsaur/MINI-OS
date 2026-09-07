# MINI-OS Runtime Library Support

`transport/lib/minilibc.c` is a modern-C implementation of a deliberately limited application runtime. Applications under `transport/apps/` and `transport/lib_test/` consume its headers while compiling as strict C90. Header names resemble standard C headers, but this is not a complete ANSI C90 library.

`transport/lib/compiler_rt.c` is also modern C and deliberately supplies the selected network build's unsigned 64-bit division and remainder helpers, but it is linked only into named network applications rather than the common runtime.

## Support Matrix

“Direct” means a checked-in executable test asserts the API's result or state.

“Exercised” means checked-in applications use the API, but do not isolate every edge case.

“Compile-time” covers declarations and definitions consumed while building strict-C90 applications.

| Area | Implemented APIs | Coverage | Important limits |
| --- | --- | --- | --- |
| Console I/O | `read`, `write`, `getchar`, `putchar`, `gets`, `fgets`, `puts` | direct for `write` and `puts`; the input APIs and `putchar` are exercised by applications | polling input; `gets` cannot receive a destination capacity and should be avoided; only console fds 0/1/2 |
| Formatting | `printf`, `sprintf`, `snprintf` | direct | `%c`, `%s`, `%d`, `%i`, `%u`, `%x`, `%p`, `%%`; optional `l` for integer conversions; no flags, width, precision, octal, or floating point |
| File streams | `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `ftell`, `rewind`, `fflush`, `feof`, `ferror` | direct | modes `r/w/a`, optional `+` and ignored `b`; unbuffered; 13 simultaneous app file descriptors; no `clearerr`, `remove`, `rename`, or temporary-file APIs |
| Memory/string | `memset`, `memcpy`, `memmove`, `memcmp`, `memchr`, `strlen`, `strcpy`, `strncpy`, `strcat`, `strncat`, `strcmp`, `strncmp`, `strchr`, `strrchr`, `strstr`, `strtok` | direct | caller supplies valid pointers and capacities; `strtok` uses one global saved position |
| Character classification | `isalpha`, `isdigit`, `isalnum`, `isspace`, `islower`, `isupper`, `isprint`, `isgraph`, `ispunct`, `isxdigit`, `iscntrl`, `toupper`, `tolower` | direct | ASCII behavior only; no locale |
| Allocation | `malloc`, `free`, `calloc`, `realloc` | direct | fixed 256 KiB heap `0x00180000..0x001BFFFF`; no invalid-pointer detection, concurrency, or process isolation |
| Conversion/math helpers | `atoi`, `strtol`, `strtoul`, `abs`, `labs` | direct | no `errno`; integer overflow is not diagnosed; `strtoul` shares the signed parser implementation |
| Algorithms/random | `qsort`, `bsearch`, `rand`, `srand` | direct | `qsort` is a simple quadratic implementation; `bsearch` requires sorted input; deterministic non-cryptographic generator |
| Definitions | `size_t`, `ptrdiff_t`, `offsetof`, `NULL`, integer limits, `assert` | compile-time | project ABI is 32-bit; `assert` behavior is not an automated test case and a failure terminates through the runtime |
| Screen helpers | `move_cursor`, `set_cursor`, `clear_screen`, `save_screen`, `restore_screen`, `get_cursor_position` | direct through the automated `vedit test` rendering check | MINI-OS extensions, not standard C APIs |

## Formatting Behavior

`snprintf` returns the number of characters that would have been emitted, NUL-terminates when size is nonzero, and accepts `NULL` only when size is zero.

An unsupported conversion is emitted literally, such as `%q`. A trailing `%` is also emitted literally.

There is no field padding, precision, sign/alternate format flag, uppercase hexadecimal, octal, or floating-point conversion.

`printf` and `puts` write directly to VGA through syscalls. File streams are unbuffered.

`fflush` is therefore an intentional no-op: it accepts either a stream pointer or `NULL` and returns zero without validating the argument.

## Stream State

- a short read at file end sets EOF without setting the error flag;
- mode violations, multiplication overflow, invalid seek, and syscall failure set the stream error flag;
- a successful seek or rewind clears EOF;
- append mode ignores the current seek position for writes;
- seeking beyond EOF is allowed, and a later write zero-fills the gap through the filesystem's cleared-block behavior;
- file size is limited by the 4,096-block data region.

Executable tests in `transport/lib_test/` compare exact strings, bytes, return values, stream flags, allocation behavior, BSS state, application-stack use, and multi-block file contents. Their success markers and the kernel's adjacent memory guards are asserted by `make test` in QEMU.
