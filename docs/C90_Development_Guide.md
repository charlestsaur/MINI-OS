# MINI-OS C90 Application Development & Execution Guide

This guide explains how to write, compile, and execute C90 applications for **MINI-OS**.

## 1. Overview

MINI-OS supports executing user-space C applications written in **ANSI C (C90 standard)**. User binaries are loaded by the kernel Shell into physical memory address `0x00040000` with stack space allocated at `0x0008F000`. System calls are routed to the kernel through the `int 0x80` interrupt gate.

## 2. C90 Programming Guidelines for MINI-OS

### 2.1 C90 Language Constraints

When writing C code for MINI-OS, adhere strictly to C90 syntax:

1. **Variable Declarations at Block Top**: All local variables must be declared at the beginning of a block before any executable statements.

   ```c
   /* Correct C90 */
   int main(void) {
       int i;
       int sum = 0;
       for (i = 0; i < 10; i++) {
           sum += i;
       }
       return 0;
   }
   ```

   *(Do not declare `for (int i = 0; ...)` inside the loop header).*

2. **Block Comments**: Use standard C comments (`/* comment */`).
3. **Dynamic Memory Allocation (`malloc`/`free`)**: Supported! Applications can dynamically allocate and free heap memory from `0x00050000` to `0x00080000` via `sys_brk` (EAX=12).
4. **No Floating-Point Operations**: The x87 FPU is not initialized in protected mode. Avoid `float` and `double` arithmetic.

### 2.2 Standard Library Support (`minilibc`)

Applications interact with MINI-OS through standard C headers (`<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<ctype.h>`, `<limits.h>`, `<stddef.h>`, `<assert.h>`). The current runtime provides the following API functions:

| Header | Key API Functions & Macros | Description |
| :--- | :--- | :--- |
| **`<stdlib.h>`** | `malloc`, `free`, `realloc`, `calloc`, `atoi`, `strtol`, `rand`, `srand`, `qsort`, `bsearch` | Dynamic heap allocation, string parsing, random generation, and sorting |
| **`<string.h>`** | `strcpy`, `strncpy`, `strcat`, `strcmp`, `strncmp`, `strchr`, `strstr`, `strtok`, `memset`, `memcpy`, `memmove`, `memcmp` | String manipulation and raw memory operations |
| **`<ctype.h>`** | `isalpha`, `isdigit`, `isalnum`, `isspace`, `islower`, `isupper`, `isprint`, `isgraph`, `ispunct`, `isxdigit`, `toupper`, `tolower` | ASCII character classification and case conversion |
| **`<stdio.h>`** | `printf`, `sprintf`, `snprintf`, `puts`, `getchar`, `putchar`, `gets`, `fgets`, `write`, `read` | Formatted console output, string formatting, and keyboard input |
| **`<limits.h>`** | `INT_MAX`, `INT_MIN`, `CHAR_BIT`, `SHRT_MAX`, `LONG_MAX`, etc. | Data type limits and integer range constants |
| **`<stddef.h>`** | `size_t`, `ptrdiff_t`, `offsetof`, `NULL` | Standard type definitions and offset macros |
| **`<assert.h>`** | `assert(expression)` | Runtime assertion testing |

## 3. Directory Layout for User Applications & Tests

User applications and C library tests are decoupled from the MINI-OS C standard library runtime:

```plaintext
transport/
├── lib/                     <-- MINI-OS C Runtime Library & Standard Headers
│   ├── crt0.asm             <-- Application Startup Entry (_start)
│   ├── minilibc.h / .c      <-- Syscall & C Standard Library Implementation
│   ├── stdio.h / stdlib.h   <-- Standard Header Wrappers
│   ├── string.h / ctype.h
│   └── limits.h / stddef.h / assert.h
├── apps/                    <-- User C Applications
│   ├── hello.c
│   ├── calc.c
│   ├── guess.c
│   └── banner.c
├── lib_test/                <-- Dedicated C Library Test Suites
│   ├── test_string.c
│   └── test_heap.c
└── build/                   <-- Compiled Output Binaries
    ├── apps/                <-- User App Executables (hello.bin, calc.bin, etc.)
    └── lib_test/            <-- Test Executables (test_string.bin, test_heap.bin)
```

### Writing a User Application (`transport/apps/hello.c`)

```c
#include "minilibc.h"

int main(void) {
    int count = 42;
    unsigned int hex_val = 0xFF;

    printf("Hello, World from C90 in MINI-OS!\n");
    printf("Test decimal: %d, Hexadecimal: 0x%x\n", count, hex_val);
    
    return 0;
}
```

## 4. Compilation and Transport Pipeline

MINI-OS uses an automated build toolchain:

```plaintext
[ transport/apps/*.c ] ──> Clang (-std=c90 -mno-sse) ──> [ build/*.o ]
                                                              │
[ crt0.o + minilibc.o ] ─────────────────────────> [ ld.lld / elf2bin ]
                                                              │
[ transport/build/*.bin ] ──> [ inject_transport ] ──> [ /external/ in mini_os.img ]
```

1. **C Runtime Startup (`crt0.asm`)**:
   - `_start` executes at entry point `0x00040000`.
   - Calls `main()`.
   - Passes `main`'s return value to `sys_exit` via `int 0x80 (EAX=1)`.

2. **Host Transport Injector (`tools/inject_transport.c`)**:
   - Built automatically during `make`.
   - Parses the MINI-OS disk image format.
   - Injects compiled binaries from `transport/build/*.bin` into the `/external/` directory on `mini_os.img`.

## 5. Building and Running User Applications

### Option A: Build All Applications

To compile all C applications in `transport/apps/` and build the OS image:

```bash
make clean
make
```

### Option B: Build a Specific Application

To compile a specific application (e.g. `calc.c`):

```bash
make app APP=calc.c
```

### Step 2: Launch QEMU Emulator

```bash
make run
```

### Step 3: Execute User Binaries in MINI-OS Shell

1. Navigate to the compiled binaries directory `/transport/build`:

   ```text
   / > cd /transport/build
   ```

2. List compiled binaries:

   ```text
   /transport/build > ls
   entries:
    - calc.bin (f)
    - guess.bin (f)
    - banner.bin (f)
    - hello.bin (f)
   ```

3. Run an application:

   ```text
   /transport/build > run calc.bin
   ```

### Expected Output in MINI-OS Console

```text
transport/build > run calc.bin
MINI_OS: launching app...
==========================================
   MINI-OS Interactive C90 Calculator
==========================================
Format: <num1> <op> <num2> (e.g. 12 + 34, 100 / 5)
Operators: +, -, *, / (Type 'q' to quit)

calc> 1+1
Result: 1 + 1 = 2

calc>
Calculator exiting...
MINI_OS: app exited cleanly.
/transport/build >
```

## 6. Execution Flow & Architecture Breakdown

```mermaid
sequenceDiagram
    participant Shell as Kernel Shell
    participant Loader as shell_run Loader
    participant App as C App (hello.bin)
    participant IDT as Syscall Handler (int 0x80)

    Shell->>Loader: Command "run hello.bin"
    Loader->>Loader: Read sectors into 0x00040000
    Loader->>Loader: Save Shell ESP -> [saved_kernel_esp]
    Loader->>Loader: Set ESP = 0x0008F000
    Loader->>App: Jump to 0x00040000 (_start -> main)
    App->>IDT: int 0x80 (EAX=4, sys_write)
    IDT->>App: Print output to VGA console & iret
    App->>IDT: int 0x80 (EAX=1, sys_exit)
    IDT->>Shell: Restore [saved_kernel_esp] & return to prompt
```

## 7. Memory Boundaries & Limitations

- **Executable Base**: `0x00040000`
- **Application Stack**: `0x0008F000` (grows downwards)
- **Maximum Application Size**: ~320 KB (code + static data + stack)
- **System Call Integers**: `sys_exit` = 1, `sys_write` = 4
