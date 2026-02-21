[bits 32]

; This file is reserved for a dedicated IDT module.
; The current kernel runs with interrupts disabled while core storage features are built.
; Keep this file as the extension point for IRQ/exception handlers.
