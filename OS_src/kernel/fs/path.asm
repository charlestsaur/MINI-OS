; ----------------------------
; Path and cwd helpers
; ----------------------------
fs_rebuild_cwd_path:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov eax, [cwd_inode]
    cmp eax, 0
    jne .build

    mov dword [cwd_path_len], 1
    mov byte [cwd_path + 0], '/'
    mov byte [cwd_path + 1], 0
    jmp .done

.build:
    ; Collect inode chain (excluding root) in PATH_PARENT_BUF as dwords.
    xor ecx, ecx
.chain_loop:
    cmp eax, 0
    je .chain_done
    cmp ecx, 15
    jg .chain_done
    mov [PATH_PARENT_BUF + ecx*4], eax
    inc ecx

    mov edi, BUF_INODE
    call fs_read_inode
    mov eax, [BUF_INODE + INODE_PARENT_OFF]
    jmp .chain_loop

.chain_done:
    mov edi, cwd_path
    mov byte [edi], '/'
    mov edx, 1

.rev_loop:
    cmp ecx, 0
    je .finalize
    dec ecx

    mov eax, [PATH_PARENT_BUF + ecx*4]
    mov edi, BUF_INODE
    call fs_read_inode

    cmp edx, 1
    je .copy_name
    mov byte [cwd_path + edx], '/'
    inc edx

.copy_name:
    mov esi, BUF_INODE + INODE_NAME_OFF
    mov ebx, INODE_NAME_LEN
.name_loop:
    mov al, [esi]
    cmp al, 0
    je .name_done
    cmp edx, 127
    jge .name_done
    mov [cwd_path + edx], al
    inc edx
    inc esi
    dec ebx
    jnz .name_loop
.name_done:
    jmp .rev_loop

.finalize:
    mov [cwd_path_len], edx
    mov byte [cwd_path + edx], 0

.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; IN: ESI=path
; OUT: EAX=inode index, -1 if invalid/not found
fs_resolve_path:
    push ebx
    push ecx
    push edx
    push edi

    cmp byte [esi], 0
    je .fail

    mov eax, [cwd_inode]
    cmp byte [esi], '/'
    jne .loop_start
    xor eax, eax

.loop_start:
.skip_slash:
    cmp byte [esi], '/'
    jne .component
    inc esi
    jmp .skip_slash

.component:
    cmp byte [esi], 0
    je .ok

    mov edi, PATH_PART_BUF
    mov ecx, DIR_ENTRY_NAME_LEN
.copy_comp:
    mov dl, [esi]
    cmp dl, 0
    je .comp_done
    cmp dl, '/'
    je .comp_done
    cmp ecx, 0
    je .fail
    mov [edi], dl
    inc edi
    inc esi
    dec ecx
    jmp .copy_comp

.comp_done:
    mov byte [edi], 0

    push eax
    mov edi, str_dot
    push esi
    mov esi, PATH_PART_BUF
    call str_eq_ci
    pop esi
    cmp al, 1
    pop eax
    je .advance

    push eax
    mov edi, str_dotdot
    push esi
    mov esi, PATH_PART_BUF
    call str_eq_ci
    pop esi
    cmp al, 1
    pop eax
    jne .lookup

    cmp eax, 0
    je .advance
    mov ebx, eax
    mov edi, BUF_INODE
    call fs_read_inode
    mov eax, [BUF_INODE + INODE_PARENT_OFF]
    jmp .advance

.lookup:
    push esi
    mov esi, PATH_PART_BUF
    call fs_find_entry_in_dir
    pop esi
    cmp eax, -1
    je .fail

.advance:
    cmp byte [esi], '/'
    jne .loop_start
    inc esi
    jmp .loop_start

.ok:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

.fail:
    mov eax, -1
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: ESI=path
; OUT: EAX=parent inode or -1; ESI=PATH_NAME_BUF
fs_split_parent_name:
    push ebx
    push ecx
    push edx
    push edi

    mov ebx, esi
    cmp byte [ebx], 0
    je .fail

    mov edx, ebx
.find_end:
    cmp byte [edx], 0
    je .trim_tail
    inc edx
    jmp .find_end

.trim_tail:
    cmp edx, ebx
    je .fail
.trim_loop:
    cmp edx, ebx
    je .fail
    cmp byte [edx - 1], '/'
    jne .find_last_slash
    dec edx
    jmp .trim_loop

.find_last_slash:
    mov ecx, edx
.scan_back:
    cmp ecx, ebx
    je .no_slash
    dec ecx
    cmp byte [ecx], '/'
    je .have_slash
    jmp .scan_back

.no_slash:
    mov eax, [cwd_inode]
    mov esi, ebx
    mov ecx, edx
    sub ecx, esi
    jmp .copy_name

.have_slash:
    mov edi, ecx
    lea esi, [edi + 1]
    mov ecx, edx
    sub ecx, esi
    push esi
    push ecx

    cmp edi, ebx
    jne .copy_parent
    xor eax, eax
    pop ecx
    pop esi
    jmp .copy_name

.copy_parent:
    mov ecx, edi
    sub ecx, ebx
    cmp ecx, 1
    jl .fail_pop_name
    cmp ecx, 63
    jg .fail_pop_name
    mov esi, ebx
    mov edi, PATH_PARENT_BUF
.parent_loop:
    mov dl, [esi]
    mov [edi], dl
    inc esi
    inc edi
    dec ecx
    jnz .parent_loop
    mov byte [edi], 0

    mov esi, PATH_PARENT_BUF
    call fs_resolve_path
    cmp eax, -1
    je .fail_pop_name

    pop ecx
    pop esi
    jmp .copy_name

.fail_pop_name:
    add esp, 8
    jmp .fail

.copy_name:
    cmp ecx, 1
    jl .fail
    cmp ecx, DIR_ENTRY_NAME_LEN
    jg .fail

    mov [tmp_parent_inode], eax
    mov edi, PATH_NAME_BUF
.name_loop:
    mov dl, [esi]
    mov [edi], dl
    inc esi
    inc edi
    dec ecx
    jnz .name_loop
    mov byte [edi], 0

    mov esi, PATH_NAME_BUF
    call fs_validate_name
    cmp al, 1
    jne .fail

    mov eax, [tmp_parent_inode]
    mov esi, PATH_NAME_BUF
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

.fail:
    mov eax, -1
    mov esi, PATH_NAME_BUF
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: ESI=name
; OUT: AL=1 valid, 0 invalid
fs_validate_name:
    push edi

    cmp byte [esi], 0
    je .bad

    mov [tmp_new_parent], esi
    mov edi, str_dot
    call str_eq_ci
    cmp al, 1
    je .bad

    mov esi, [tmp_new_parent]
    mov edi, str_dotdot
    call str_eq_ci
    cmp al, 1
    je .bad

    mov al, 1
    pop edi
    ret

.bad:
    xor al, al
    pop edi
    ret
