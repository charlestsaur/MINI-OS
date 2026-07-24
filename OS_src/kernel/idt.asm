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
; EAX = syscall number (1=sys_exit, 3=sys_read, 4=sys_write)
; EBX = arg1 (exit_code / fd)
; ECX = arg2 (buf)
; EDX = arg3 (count)
syscall_entry:
    cmp eax, 1
    je near .sys_exit
    cmp eax, 3
    je near .sys_read
    cmp eax, 4
    je near .sys_write

    ; Unknown syscall -> iret
    iret

.sys_exit:
    ; Restore Shell stack and return to Shell
    mov esp, [saved_kernel_esp]
    jmp strict dword return_to_shell

.sys_read:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov edi, ecx         ; Destination buffer
    xor esi, esi         ; Bytes read counter = 0

.sys_read_loop:
    cmp esi, edx         ; Reached max requested bytes?
    jge near .sys_read_done

    call kbd_read_char_blocking
    test al, al          ; Ignore 0 (key releases / unmapped keys)
    jz near .sys_read_loop

    cmp al, 13           ; Carriage return -> newline
    je near .sys_read_newline
    cmp al, 10           ; Line feed -> newline
    je near .sys_read_newline

    ; Check backspace (8)
    cmp al, 8
    jne near .sys_read_store_char

    ; Backspace pressed
    test esi, esi
    jz near .sys_read_loop    ; Nothing to backspace
    dec esi
    dec edi
    ; Echo backspace to VGA console (backspace, space, backspace)
    call vga_putc
    mov al, ' '
    call vga_putc
    mov al, 8
    call vga_putc
    jmp near .sys_read_loop

.sys_read_store_char:
    ; Store ASCII char in buffer
    mov [edi], al
    inc edi
    inc esi

    ; Echo character to VGA screen
    call vga_putc
    jmp near .sys_read_loop

.sys_read_newline:
    mov byte [edi], 0    ; Null-terminate string buffer
    mov al, 10
    call vga_putc        ; Echo newline

.sys_read_done:
    mov [tmp_read_cnt], esi ; Store result
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    mov eax, [tmp_read_cnt] ; Return byte count in EAX
    iret

.sys_write:
    pusha
    mov esi, ecx            ; buffer pointer
    mov ecx, edx            ; length
    call vga_print_n
    popa
    iret

tmp_read_cnt dd 0



