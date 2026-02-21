; ----------------------------
; ATA PIO (LBA28)
; ----------------------------
; IN: EAX=lba, EDI=destination buffer (512 bytes)
ata_read_sector_lba28:
    push eax
    push ebx
    push ecx
    push edx
    push edi

    mov ebx, eax
    call ata_wait_not_busy

    mov dx, ATA_SECTOR_COUNT
    mov al, 1
    out dx, al

    mov dx, ATA_LBA_LOW
    mov al, bl
    out dx, al

    mov dx, ATA_LBA_MID
    mov al, bh
    out dx, al

    shr ebx, 16
    mov dx, ATA_LBA_HIGH
    mov al, bl
    out dx, al

    mov dx, ATA_DRIVE_HEAD
    mov al, bh
    and al, 0x0F
    or al, 0xE0
    out dx, al

    mov dx, ATA_COMMAND_STATUS
    mov al, ATA_CMD_READ
    out dx, al

    call ata_wait_drq

    mov dx, ATA_DATA_PORT
    mov ecx, 256
    rep insw

    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; IN: EAX=lba, ESI=source buffer (512 bytes)
ata_write_sector_lba28:
    push eax
    push ebx
    push ecx
    push edx
    push esi

    mov ebx, eax
    call ata_wait_not_busy

    mov dx, ATA_SECTOR_COUNT
    mov al, 1
    out dx, al

    mov dx, ATA_LBA_LOW
    mov al, bl
    out dx, al

    mov dx, ATA_LBA_MID
    mov al, bh
    out dx, al

    shr ebx, 16
    mov dx, ATA_LBA_HIGH
    mov al, bl
    out dx, al

    mov dx, ATA_DRIVE_HEAD
    mov al, bh
    and al, 0x0F
    or al, 0xE0
    out dx, al

    mov dx, ATA_COMMAND_STATUS
    mov al, ATA_CMD_WRITE
    out dx, al

    call ata_wait_drq

    mov dx, ATA_DATA_PORT
    mov ecx, 256
    rep outsw

    mov dx, ATA_COMMAND_STATUS
    mov al, 0xE7
    out dx, al
    call ata_wait_not_busy

    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

ata_wait_not_busy:
    push ecx
    push edx
    mov ecx, 0x100000
.wait:
    mov dx, ATA_COMMAND_STATUS
    in al, dx
    test al, 0x80
    jz .done
    loop .wait
.done:
    pop edx
    pop ecx
    ret

ata_wait_drq:
    push ecx
    push edx
    mov ecx, 0x100000
.wait:
    mov dx, ATA_COMMAND_STATUS
    in al, dx
    test al, 0x80
    jnz .cont
    test al, 0x08
    jnz .ready
.cont:
    loop .wait
.ready:
    pop edx
    pop ecx
    ret

; ----------------------------
; Keyboard (polling)
; ----------------------------
; IN: EDI = buffer, ECX = max length
; OUT: EAX = length (excluding terminator)
kbd_read_line:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    xor ebx, ebx
.loop:
    call kbd_read_char_blocking
    cmp al, 13
    je .enter
    cmp al, 8
    je .backspace
    cmp al, 0
    je .loop

    cmp ebx, ecx
    jge .loop

    mov [edi + ebx], al
    push eax
    call vga_putc
    pop eax
    inc ebx
    jmp .loop

.backspace:
    cmp ebx, 0
    je .loop
    dec ebx
    mov byte [edi + ebx], 0
    call vga_backspace
    jmp .loop

.enter:
    mov byte [edi + ebx], 0
    call vga_newline
    mov eax, ebx

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EDI = buffer, ECX = max length
; OUT: EAX = length (excluding terminator)
; Behavior: Enter inserts newline, ESC finishes editing.
kbd_read_text:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    xor ebx, ebx
.loop:
    call kbd_read_char_blocking
    cmp al, 27
    je .finish
    cmp al, 13
    je .enter
    cmp al, 8
    je .backspace
    cmp al, 0
    je .loop

    cmp ebx, ecx
    jge .loop
    mov [edi + ebx], al
    push eax
    call vga_putc
    pop eax
    inc ebx
    jmp .loop

.enter:
    cmp ebx, ecx
    jge .loop
    mov byte [edi + ebx], 10
    inc ebx
    call vga_newline
    jmp .loop

.backspace:
    cmp ebx, 0
    je .loop
    dec ebx
    cmp byte [edi + ebx], 10
    je .bs_newline
    mov byte [edi + ebx], 0
    call vga_backspace
    jmp .loop

.bs_newline:
    mov byte [edi + ebx], 0
    jmp .loop

.finish:
    mov byte [edi + ebx], 0
    call vga_newline
    mov eax, ebx

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; OUT: AL = ASCII char, 0 if unsupported
kbd_read_char_blocking:
.wait_key:
    mov dx, KBD_STATUS_PORT
    in al, dx
    test al, 1
    jz .wait_key

    mov dx, KBD_DATA_PORT
    in al, dx

    cmp al, 0x80
    jae .unsupported

    cmp al, 0x1C
    je .enter
    cmp al, 0x01
    je .esc
    cmp al, 0x0E
    je .backspace
    cmp al, 0x39
    je .space

    cmp al, 0x02
    jb .letters
    cmp al, 0x0A
    jbe .num_1_9
    cmp al, 0x0B
    je .num_0

.letters:
    cmp al, 0x1E
    je .a
    cmp al, 0x30
    je .b
    cmp al, 0x2E
    je .c
    cmp al, 0x20
    je .d
    cmp al, 0x12
    je .e
    cmp al, 0x21
    je .f
    cmp al, 0x22
    je .g
    cmp al, 0x23
    je .h
    cmp al, 0x17
    je .i
    cmp al, 0x24
    je .j
    cmp al, 0x25
    je .k
    cmp al, 0x26
    je .l
    cmp al, 0x32
    je .m
    cmp al, 0x31
    je .n
    cmp al, 0x18
    je .o
    cmp al, 0x19
    je .p
    cmp al, 0x10
    je .q
    cmp al, 0x13
    je .r
    cmp al, 0x1F
    je .s
    cmp al, 0x14
    je .t
    cmp al, 0x16
    je .u
    cmp al, 0x2F
    je .v
    cmp al, 0x11
    je .w
    cmp al, 0x2D
    je .x
    cmp al, 0x15
    je .y
    cmp al, 0x2C
    je .z

    cmp al, 0x34
    je .dot
    cmp al, 0x35
    je .slash
    cmp al, 0x0C
    je .minus
    cmp al, 0x0D
    je .equal

.unsupported:
    xor al, al
    ret

.num_1_9:
    add al, '1' - 0x02
    ret

.num_0:
    mov al, '0'
    ret

.enter:
    mov al, 13
    ret

.esc:
    mov al, 27
    ret

.backspace:
    mov al, 8
    ret

.space:
    mov al, ' '
    ret

.dot:
    mov al, '.'
    ret

.slash:
    mov al, '/'
    ret

.minus:
    mov al, '-'
    ret

.equal:
    mov al, '='
    ret

.a: mov al, 'a'
    ret
.b: mov al, 'b'
    ret
.c: mov al, 'c'
    ret
.d: mov al, 'd'
    ret
.e: mov al, 'e'
    ret
.f: mov al, 'f'
    ret
.g: mov al, 'g'
    ret
.h: mov al, 'h'
    ret
.i: mov al, 'i'
    ret
.j: mov al, 'j'
    ret
.k: mov al, 'k'
    ret
.l: mov al, 'l'
    ret
.m: mov al, 'm'
    ret
.n: mov al, 'n'
    ret
.o: mov al, 'o'
    ret
.p: mov al, 'p'
    ret
.q: mov al, 'q'
    ret
.r: mov al, 'r'
    ret
.s: mov al, 's'
    ret
.t: mov al, 't'
    ret
.u: mov al, 'u'
    ret
.v: mov al, 'v'
    ret
.w: mov al, 'w'
    ret
.x: mov al, 'x'
    ret
.y: mov al, 'y'
    ret
.z: mov al, 'z'
    ret

; ----------------------------
; VGA text console
; ----------------------------
vga_clear:
    push eax
    push ecx
    push edi

    mov eax, (VGA_ATTR << 8) | ' '
    mov edi, VGA_BUFFER
    mov ecx, VGA_WIDTH * VGA_HEIGHT
    rep stosw

    mov dword [cursor_row], 0
    mov dword [cursor_col], 0
    call vga_sync_cursor

    pop edi
    pop ecx
    pop eax
    ret

; IN: AL=character
vga_putc:
    push eax
    push ebx
    push edx
    push edi

    cmp al, 10
    je .newline

    mov ebx, [cursor_row]
    imul ebx, VGA_WIDTH
    add ebx, [cursor_col]
    shl ebx, 1
    mov edi, VGA_BUFFER
    add edi, ebx

    mov ah, VGA_ATTR
    mov [edi], ax

    mov edx, [cursor_col]
    inc edx
    cmp edx, VGA_WIDTH
    jl .store_col
    mov edx, 0
    mov ebx, [cursor_row]
    inc ebx
    cmp ebx, VGA_HEIGHT
    jl .store_row
    call vga_scroll_up
    mov ebx, VGA_HEIGHT - 1
.store_row:
    mov [cursor_row], ebx
.store_col:
    mov [cursor_col], edx
    jmp .done

.newline:
    call vga_newline

.done:
    call vga_sync_cursor
    pop edi
    pop edx
    pop ebx
    pop eax
    ret

vga_backspace:
    push eax
    push ebx

    mov ebx, [cursor_col]
    cmp ebx, 0
    je .done

    dec ebx
    mov [cursor_col], ebx
    mov al, ' '
    call vga_putc

    mov ebx, [cursor_col]
    cmp ebx, 0
    je .done
    dec ebx
    mov [cursor_col], ebx

.done:
    call vga_sync_cursor
    pop ebx
    pop eax
    ret

vga_newline:
    push eax
    mov dword [cursor_col], 0
    mov eax, [cursor_row]
    inc eax
    cmp eax, VGA_HEIGHT
    jl .set_row
    call vga_scroll_up
    mov eax, VGA_HEIGHT - 1
.set_row:
    mov [cursor_row], eax
    call vga_sync_cursor
    pop eax
    ret

vga_scroll_up:
    push eax
    push ecx
    push esi
    push edi

    ; Move rows 1..24 to rows 0..23.
    mov esi, VGA_BUFFER + (VGA_WIDTH * 2)
    mov edi, VGA_BUFFER
    mov ecx, VGA_WIDTH * (VGA_HEIGHT - 1)
    rep movsw

    ; Clear last row.
    mov eax, (VGA_ATTR << 8) | ' '
    mov ecx, VGA_WIDTH
    rep stosw

    pop edi
    pop esi
    pop ecx
    pop eax
    ret

vga_sync_cursor:
    push eax
    push ebx
    push edx

    mov eax, [cursor_row]
    imul eax, VGA_WIDTH
    add eax, [cursor_col]
    mov ebx, eax

    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    mov dx, 0x3D5
    mov al, bl
    out dx, al

    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    mov dx, 0x3D5
    mov al, bh
    out dx, al

    pop edx
    pop ebx
    pop eax
    ret

; IN: ESI=zero-terminated string
vga_print:
    push eax
.loop:
    lodsb
    test al, al
    jz .done
    call vga_putc
    jmp .loop
.done:
    pop eax
    ret

; IN: ESI=string, ECX=length
vga_print_n:
    push eax
.loop:
    cmp ecx, 0
    je .done
    lodsb
    call vga_putc
    dec ecx
    jmp .loop
.done:
    pop eax
    ret

; IN: ESI=fixed-length name field (max 27), stops at 0
vga_print_name:
    push eax
    push ecx
    mov ecx, INODE_NAME_LEN
.loop:
    lodsb
    test al, al
    jz .done
    call vga_putc
    loop .loop
.done:
    pop ecx
    pop eax
    ret
