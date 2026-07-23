[bits 32]

; ----------------------------
; IDT & System Call Module
; ----------------------------
IDT_BASE equ 0x26000

idt_descriptor:
    dw (256 * 8) - 1
    dd IDT_BASE

idt_init:
    push eax
    push ecx
    push edi

    ; Zero IDT memory at 0x26000 (2048 bytes)
    mov edi, IDT_BASE
    mov ecx, 256 * 8
    call zero_buffer

    ; Register int 0x80 (syscall) at entry 0x80 (128)
    mov edi, IDT_BASE + (0x80 * 8)
    mov eax, syscall_entry

    mov [edi], ax            ; Offset 0..15
    mov word [edi + 2], 0x08  ; Segment Selector (Code Segment)
    mov byte [edi + 4], 0    ; Reserved
    mov byte [edi + 5], 0xEE  ; Type_attr: Present, Ring 3, 32-bit Interrupt Gate
    shr eax, 16
    mov [edi + 6], ax        ; Offset 16..31

    lidt [idt_descriptor]

    pop edi
    pop ecx
    pop eax
    ret

; ----------------------------
; System Call Handler (int 0x80)
; ----------------------------
; EAX = syscall number (1=sys_exit, 4=sys_write)
; EBX = arg1 (exit_code / fd)
; ECX = arg2 (buf)
; EDX = arg3 (count)
syscall_entry:
    cmp eax, 1
    je .sys_exit
    cmp eax, 4
    je .sys_write

    ; Unknown syscall -> iret
    iret

.sys_exit:
    ; Restore Shell stack and return to Shell
    mov esp, [saved_kernel_esp]
    jmp strict dword return_to_shell

.sys_write:
    pusha
    mov esi, ecx            ; buffer pointer
    mov ecx, edx            ; length
    call vga_print_n
    popa
    iret

