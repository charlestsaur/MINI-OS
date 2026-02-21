[bits 32]

; This file is reserved for a dedicated GDT module.
; The current bootloader sets up a flat 32-bit GDT before jumping to OS_src/kernel/main.asm.
; Keep this file as the extension point when GDT management moves into the kernel.
