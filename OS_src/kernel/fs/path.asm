; ----------------------------
; Path and current-directory helpers
; ----------------------------

; IN: EAX=inode index
; OUT: EAX=FS_OK, or FS_ERR_CORRUPT if invalid/already visited
fs_path_visit_inode:
    push ebx
    push ecx
    push edx

    cmp eax, 1
    jb .corrupt
    cmp eax, FS_INODE_COUNT
    jae .corrupt
    mov ebx, eax
    mov ecx, eax
    shr ebx, 3
    and ecx, 7
    mov dl, 1
    shl dl, cl
    test [FS_VISITED_BUF + ebx], dl
    jnz .corrupt
    or [FS_VISITED_BUF + ebx], dl
    mov eax, FS_OK
    jmp .done

.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=parent directory inode, ESI=child name
; OUT: EAX=FS_OK or a filesystem error
fs_validate_child_path:
    push ebx
    push ecx
    push edx
    push ebp
    push esi
    push edi

    mov ebx, eax
    xor edx, edx
.child_len:
    cmp byte [esi + edx], 0
    je .child_len_done
    inc edx
    cmp edx, DIR_ENTRY_NAME_LEN
    ja .too_long
    jmp .child_len
.child_len_done:
    cmp edx, 0
    je .invalid
    inc edx                         ; Leading slash.
    mov ecx, 1                     ; Child component depth.
    call fs_chain_reset

.parent_loop:
    cmp ebx, 0
    je .success
    cmp ecx, FS_MAX_DEPTH
    jae .too_long
    mov eax, ebx
    call fs_path_visit_inode
    cmp eax, FS_OK
    jl .done

    mov eax, ebx
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .not_dir

    inc edx                         ; Separator before this parent.
    cmp edx, FS_MAX_PATH
    ja .too_long
    xor ebp, ebp
.parent_name:
    cmp ebp, INODE_NAME_LEN
    jae .parent_name_done
    mov al, [BUF_INODE + INODE_NAME_OFF + ebp]
    test al, al
    jz .parent_name_done
    inc edx
    cmp edx, FS_MAX_PATH
    ja .too_long
    inc ebp
    jmp .parent_name
.parent_name_done:
    cmp ebp, 0
    je .corrupt
    mov ebx, [BUF_INODE + INODE_PARENT_OFF]
    cmp ebx, FS_INODE_COUNT
    jae .corrupt
    inc ecx
    jmp .parent_loop

.success:
    mov eax, FS_OK
    jmp .done
.not_dir:
    mov eax, FS_ERR_NOT_DIR
    jmp .done
.invalid:
    mov eax, FS_ERR_INVALID
    jmp .done
.too_long:
    mov eax, FS_ERR_PATH_TOO_LONG
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop esi
    pop ebp
    pop edx
    pop ecx
    pop ebx
    ret

; OUT: EAX=FS_OK or a filesystem error
fs_rebuild_cwd_path:
    push ebx
    push ecx
    push edx
    push ebp
    push esi
    push edi

    mov eax, [cwd_inode]
    cmp eax, 0
    jne .collect
    mov dword [cwd_path_len], 1
    mov byte [cwd_path], '/'
    mov byte [cwd_path + 1], 0
    mov eax, FS_OK
    jmp .done

.collect:
    xor ecx, ecx
    call fs_chain_reset
.chain_loop:
    cmp eax, 0
    je .chain_done
    cmp ecx, FS_MAX_DEPTH
    jae .too_long
    mov ebx, eax
    call fs_path_visit_inode
    cmp eax, FS_OK
    jl .done
    mov [PATH_PARENT_BUF + ecx * 4], ebx
    inc ecx

    mov eax, ebx
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .corrupt
    mov eax, [BUF_INODE + INODE_PARENT_OFF]
    cmp eax, FS_INODE_COUNT
    jae .corrupt
    jmp .chain_loop

.chain_done:
    mov edi, PATH_BUILD_BUF
    mov byte [edi], '/'
    mov edx, 1

.reverse_loop:
    cmp ecx, 0
    je .commit
    dec ecx
    mov eax, [PATH_PARENT_BUF + ecx * 4]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done

    cmp edx, 1
    je .copy_name
    cmp edx, FS_MAX_PATH
    jae .too_long
    mov byte [PATH_BUILD_BUF + edx], '/'
    inc edx

.copy_name:
    mov esi, BUF_INODE + INODE_NAME_OFF
    xor ebp, ebp
.name_loop:
    cmp ebp, INODE_NAME_LEN
    jae .name_done
    mov al, [esi + ebp]
    test al, al
    jz .name_done
    cmp edx, FS_MAX_PATH
    jae .too_long
    mov [PATH_BUILD_BUF + edx], al
    inc edx
    inc ebp
    jmp .name_loop
.name_done:
    cmp ebp, 0
    je .corrupt
    jmp .reverse_loop

.commit:
    mov byte [PATH_BUILD_BUF + edx], 0
    mov [cwd_path_len], edx
    mov esi, PATH_BUILD_BUF
    mov edi, cwd_path
    call copy_string
    mov eax, FS_OK
    jmp .done

.too_long:
    mov eax, FS_ERR_PATH_TOO_LONG
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop esi
    pop ebp
    pop edx
    pop ecx
    pop ebx
    ret

; IN: ESI=path
; OUT: EAX=inode index or a filesystem error
fs_resolve_path:
    push ebx
    push ecx
    push edx
    push ebp
    push edi

    cmp byte [esi], 0
    je .invalid

    mov edi, esi
.find_end:
    cmp byte [edi], 0
    je .end_found
    inc edi
    jmp .find_end
.end_found:
    xor ebp, ebp
    cmp edi, esi
    je .invalid
    cmp byte [edi - 1], '/'
    jne .select_start
    mov ebp, 1

.select_start:
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
    je .finish
    mov edi, PATH_PART_BUF
    mov ecx, DIR_ENTRY_NAME_LEN

.copy_component:
    mov dl, [esi]
    cmp dl, 0
    je .component_done
    cmp dl, '/'
    je .component_done
    cmp ecx, 0
    je .invalid
    mov [edi], dl
    inc edi
    inc esi
    dec ecx
    jmp .copy_component

.component_done:
    mov byte [edi], 0
    push eax
    push esi
    mov esi, PATH_PART_BUF
    mov edi, str_dot
    call str_eq_ci
    mov dl, al
    pop esi
    pop eax
    cmp dl, 1
    je .advance

    push eax
    push esi
    mov esi, PATH_PART_BUF
    mov edi, str_dotdot
    call str_eq_ci
    mov dl, al
    pop esi
    pop eax
    cmp dl, 1
    jne .lookup

    cmp eax, 0
    je .advance
    mov ebx, eax
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    mov eax, [BUF_INODE + INODE_PARENT_OFF]
    cmp eax, FS_INODE_COUNT
    jae .corrupt
    jmp .advance

.lookup:
    push esi
    mov esi, PATH_PART_BUF
    call fs_find_entry_in_dir
    pop esi
    cmp eax, FS_OK
    jl .done

.advance:
    cmp byte [esi], '/'
    jne .loop_start
    inc esi
    jmp .loop_start

.finish:
    cmp ebp, 0
    je .done
    mov [tmp_inode_idx], eax
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .not_dir
    mov eax, [tmp_inode_idx]
    jmp .done

.not_dir:
    mov eax, FS_ERR_NOT_DIR
    jmp .done
.invalid:
    mov eax, FS_ERR_INVALID
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop ebp
    pop edx
    pop ecx
    pop ebx
    ret

; IN: ESI=path
; OUT: AL=1 only when path contains one or more '/' and nothing else
fs_path_is_root:
    push esi
    cmp byte [esi], '/'
    jne .no
.loop:
    cmp byte [esi], '/'
    jne .end
    inc esi
    jmp .loop
.end:
    cmp byte [esi], 0
    jne .no
    mov al, 1
    pop esi
    ret
.no:
    xor al, al
    pop esi
    ret

; IN: ESI=path
; OUT: EAX=parent inode or a filesystem error; ESI=PATH_NAME_BUF
fs_split_parent_name:
    push ebx
    push ecx
    push edx
    push edi

    mov ebx, esi
    cmp byte [ebx], 0
    je .invalid
    mov edx, ebx
.find_path_end:
    cmp byte [edx], 0
    je .path_end
    inc edx
    jmp .find_path_end
.path_end:
    cmp edx, ebx
    je .invalid
    cmp byte [edx - 1], '/'
    je .invalid

    mov ecx, edx
.scan_back:
    cmp ecx, ebx
    je .no_slash
    dec ecx
    cmp byte [ecx], '/'
    jne .scan_back
    jmp .have_slash

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
    jl .invalid_pop_name
    cmp ecx, FS_MAX_PATH
    ja .too_long_pop_name
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
    cmp eax, FS_OK
    jl .parent_error
    mov [tmp_parent_inode], eax
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .parent_error
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .parent_not_dir
    mov eax, [tmp_parent_inode]
    pop ecx
    pop esi
    jmp .copy_name

.parent_not_dir:
    mov eax, FS_ERR_NOT_DIR
.parent_error:
    add esp, 8
    jmp .done
.invalid_pop_name:
    add esp, 8
    jmp .invalid
.too_long_pop_name:
    add esp, 8
    jmp .too_long

.copy_name:
    cmp ecx, 1
    jl .invalid
    cmp ecx, DIR_ENTRY_NAME_LEN
    ja .invalid
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
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_parent_inode]
    mov esi, PATH_NAME_BUF
    call fs_validate_child_path
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_parent_inode]
    mov esi, PATH_NAME_BUF
    jmp .done

.invalid:
    mov eax, FS_ERR_INVALID
    jmp .done
.too_long:
    mov eax, FS_ERR_PATH_TOO_LONG
.done:
    mov esi, PATH_NAME_BUF
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: ESI=name
; OUT: EAX=FS_OK or FS_ERR_INVALID
fs_validate_name:
    push ecx
    push edi

    cmp byte [esi], 0
    je .bad
    xor ecx, ecx
.scan:
    mov al, [esi + ecx]
    test al, al
    jz .length_ok
    cmp al, '/'
    je .bad
    inc ecx
    cmp ecx, DIR_ENTRY_NAME_LEN
    ja .bad
    jmp .scan

.length_ok:
    push esi
    mov edi, str_dot
    call str_eq_ci
    pop esi
    cmp al, 1
    je .bad
    push esi
    mov edi, str_dotdot
    call str_eq_ci
    pop esi
    cmp al, 1
    je .bad
    mov eax, FS_OK
    jmp .done

.bad:
    mov eax, FS_ERR_INVALID
.done:
    pop edi
    pop ecx
    ret
