; ----------------------------
; Generic helpers
; ----------------------------
; IN: EDI=buffer, ECX=byte count
zero_buffer:
    push eax
    push ecx
    push edi
    xor eax, eax
    rep stosb
    pop edi
    pop ecx
    pop eax
    ret

; IN: EDI points to a 512-byte sector buffer
zero_sector:
    push ecx
    mov ecx, 512
    call zero_buffer
    pop ecx
    ret

; IN: ESI=src, EDI=dst, ECX=bytes
copy_bytes:
    push ecx
    rep movsb
    pop ecx
    ret

; IN: ESI=src zero-terminated, EDI=dst
copy_string:
    push eax
.loop:
    lodsb
    stosb
    test al, al
    jnz .loop
    pop eax
    ret

; IN: ESI=src zero-terminated, EDI=dst fixed 27 bytes
copy_name_27:
    push eax
    push ecx
    mov ecx, INODE_NAME_LEN
.copy:
    cmp ecx, 0
    je .done
    lodsb
    stosb
    dec ecx
    test al, al
    jz .pad
    jmp .copy
.pad:
    xor al, al
.pad_loop:
    cmp ecx, 0
    je .done
    stosb
    dec ecx
    jmp .pad_loop
.done:
    pop ecx
    pop eax
    ret

; IN: AL
; OUT: AL uppercased if a-z
char_to_upper:
    cmp al, 'a'
    jb .done
    cmp al, 'z'
    ja .done
    sub al, 32
.done:
    ret

; IN: ESI=str1, EDI=str2 (both 0-terminated)
; OUT: AL=1 equal, 0 not equal (case-insensitive)
str_eq_ci:
    push ebx
.loop:
    mov al, [esi]
    mov bl, [edi]

    push eax
    call char_to_upper
    mov dl, al
    pop eax

    mov al, bl
    call char_to_upper
    mov bl, al

    cmp dl, bl
    jne .no

    cmp dl, 0
    je .yes

    inc esi
    inc edi
    jmp .loop

.yes:
    mov al, 1
    pop ebx
    ret

.no:
    mov al, 0
    pop ebx
    ret

; IN: ESI=input string, EDI=inode name field (27 bytes)
; OUT: AL=1 equal, 0 not equal (case-insensitive)
name_field_eq_input:
    push ebx
    push ecx

    mov ecx, INODE_NAME_LEN
.loop:
    mov al, [esi]
    mov bl, [edi]

    push eax
    call char_to_upper
    mov dl, al
    pop eax

    mov al, bl
    call char_to_upper
    mov bl, al

    cmp dl, bl
    jne .no

    cmp dl, 0
    je .yes

    inc esi
    inc edi
    dec ecx
    jnz .loop

    cmp byte [esi], 0
    jne .no

.yes:
    mov al, 1
    pop ecx
    pop ebx
    ret

.no:
    mov al, 0
    pop ecx
    pop ebx
    ret
