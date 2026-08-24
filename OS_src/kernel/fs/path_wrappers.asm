; ----------------------------
; Path wrappers used by the shell and syscalls
; ----------------------------

; IN: ESI=path
; OUT: EAX=inode or a filesystem error
fs_lookup_path:
    call fs_resolve_path
    ret

; IN: ESI=path
; OUT: EAX=FS_OK or a filesystem error
fs_change_dir_path:
    call fs_resolve_path
    cmp eax, FS_OK
    jl .done
    mov [tmp_inode_idx], eax

    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .not_dir

    mov eax, [cwd_inode]
    mov [tmp_parent_inode], eax
    mov eax, [tmp_inode_idx]
    mov [cwd_inode], eax
    call fs_rebuild_cwd_path
    cmp eax, FS_OK
    jge .done

    mov [tmp_chain_count], eax
    mov eax, [tmp_parent_inode]
    mov [cwd_inode], eax
    call fs_rebuild_cwd_path
    mov eax, [tmp_chain_count]
    ret

.not_dir:
    mov eax, FS_ERR_NOT_DIR
.done:
    ret

; IN: ESI=path
; OUT: EAX=created inode or a filesystem error
fs_create_file_path:
    push esi
    call fs_begin_mutation
    pop esi
    cmp eax, FS_OK
    jl .done
    call fs_split_parent_name
    cmp eax, FS_OK
    jl .complete
    call fs_create_file_in_dir
.complete:
    call fs_complete_mutation
.done:
    ret

; IN: ESI=path
; OUT: EAX=FS_OK or a filesystem error
fs_create_dir_path:
    push esi
    call fs_begin_mutation
    pop esi
    cmp eax, FS_OK
    jl .done
    call fs_split_parent_name
    cmp eax, FS_OK
    jl .complete
    call fs_create_dir_in_dir
.complete:
    call fs_complete_mutation
.done:
    ret

; IN: ESI=path
; OUT: EAX=FS_OK or a filesystem error
fs_remove_path:
    push esi
    call fs_begin_mutation
    pop esi
    cmp eax, FS_OK
    jl .done
    push esi
    call fs_path_is_root
    pop esi
    cmp al, 1
    je .protected
    call fs_split_parent_name
    cmp eax, FS_OK
    jl .complete
    call fs_remove_entry_in_dir
    jmp .complete
.protected:
    mov eax, FS_ERR_PROTECTED
.complete:
    call fs_complete_mutation
.done:
    ret

; IN: ESI=old path, EDI=new path
; OUT: EAX=FS_OK or a filesystem error
fs_rename_path:
    mov [tmp_mv_old_path], esi
    mov [tmp_mv_new_path], edi
    push esi
    push edi
    call fs_begin_mutation
    pop edi
    pop esi
    cmp eax, FS_OK
    jl .done
    call fs_rename_path_mutation
    call fs_complete_mutation
.done:
    ret

fs_rename_path_mutation:
    mov [tmp_mv_old_path], esi
    mov [tmp_mv_new_path], edi

    mov esi, [tmp_mv_old_path]
    call fs_split_parent_name
    cmp eax, FS_OK
    jl .done
    mov [tmp_mv_old_parent], eax
    mov esi, PATH_NAME_BUF
    mov edi, PATH_OLD_NAME_BUF
    call copy_string

    mov esi, [tmp_mv_new_path]
    call fs_split_parent_name
    cmp eax, FS_OK
    jl .done
    mov [tmp_mv_new_parent], eax
    mov esi, PATH_NAME_BUF
    mov edi, PATH_NEW_NAME_BUF
    call copy_string

    mov eax, [tmp_mv_old_parent]
    mov esi, PATH_OLD_NAME_BUF
    call fs_find_entry_in_dir
    cmp eax, FS_OK
    jl .done
    mov [tmp_child_inode], eax
    mov [tmp_old_entry_idx], ebx
    mov [tmp_type], dl

    mov eax, [tmp_mv_old_parent]
    cmp eax, [tmp_mv_new_parent]
    jne .lookup_destination
    push esi
    push edi
    mov esi, PATH_OLD_NAME_BUF
    mov edi, PATH_NEW_NAME_BUF
    call str_eq
    pop edi
    pop esi
    cmp al, 1
    je .success

.lookup_destination:
    mov eax, [tmp_mv_new_parent]
    mov esi, PATH_NEW_NAME_BUF
    call fs_find_entry_in_dir
    cmp eax, FS_ERR_NOT_FOUND
    je .validate_move
    cmp eax, FS_OK
    jl .done

    cmp eax, [tmp_child_inode]
    jne .exists
    mov eax, [tmp_mv_old_parent]
    cmp eax, [tmp_mv_new_parent]
    jne .exists
    mov ebx, [tmp_old_entry_idx]
    jmp .case_only

.validate_move:
    cmp byte [tmp_type], 2
    jne .check_cwd
    mov eax, [tmp_mv_new_parent]
    mov ebx, [tmp_child_inode]
    call fs_parent_contains_inode
    cmp eax, FS_OK
    jl .done
    cmp eax, 1
    je .invalid

.check_cwd:
    mov eax, [cwd_inode]
    mov ebx, [tmp_child_inode]
    call fs_parent_contains_inode
    cmp eax, FS_OK
    jl .done
    mov [tmp_cwd_affected], al

    mov eax, [tmp_mv_new_parent]
    mov esi, PATH_NEW_NAME_BUF
    call fs_validate_child_path
    cmp eax, FS_OK
    jl .done

    mov eax, [tmp_mv_new_parent]
    call fs_find_free_entry_in_dir
    cmp eax, FS_OK
    jl .done
    mov [tmp_new_entry_idx], ebx

    mov eax, [tmp_mv_new_parent]
    mov ebx, [tmp_new_entry_idx]
    mov ecx, [tmp_child_inode]
    mov dl, [tmp_type]
    mov esi, PATH_NEW_NAME_BUF
    call fs_write_entry_in_dir
    cmp eax, FS_OK
    jl .done

    mov eax, [tmp_child_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .rollback_destination
    mov edi, BUF_INODE + INODE_NAME_OFF
    mov esi, PATH_NEW_NAME_BUF
    call copy_name_27
    mov eax, [tmp_mv_new_parent]
    mov [BUF_INODE + INODE_PARENT_OFF], eax
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .rollback_destination

    mov eax, [tmp_mv_old_parent]
    mov ebx, [tmp_old_entry_idx]
    call fs_clear_entry_in_dir
    cmp eax, FS_OK
    jl .rollback_inode_and_destination
    jmp .refresh_cwd

.case_only:
    mov eax, [cwd_inode]
    mov ebx, [tmp_child_inode]
    call fs_parent_contains_inode
    cmp eax, FS_OK
    jl .done
    mov [tmp_cwd_affected], al

    mov eax, [tmp_child_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    mov edi, BUF_INODE + INODE_NAME_OFF
    mov esi, PATH_NEW_NAME_BUF
    call copy_name_27
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .done

    mov eax, [tmp_mv_old_parent]
    mov ebx, [tmp_old_entry_idx]
    mov ecx, [tmp_child_inode]
    mov dl, [tmp_type]
    mov esi, PATH_NEW_NAME_BUF
    call fs_write_entry_in_dir
    cmp eax, FS_OK
    jl .rollback_case_inode
    jmp .refresh_cwd

.rollback_case_inode:
    mov [tmp_chain_count], eax
    mov eax, [tmp_child_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    mov edi, BUF_INODE + INODE_NAME_OFF
    mov esi, PATH_OLD_NAME_BUF
    call copy_name_27
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_chain_count]
    ret

.rollback_inode_and_destination:
    mov [tmp_chain_count], eax
    mov eax, [tmp_child_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    mov edi, BUF_INODE + INODE_NAME_OFF
    mov esi, PATH_OLD_NAME_BUF
    call copy_name_27
    mov eax, [tmp_mv_old_parent]
    mov [BUF_INODE + INODE_PARENT_OFF], eax
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .done
    jmp .clear_destination

.rollback_destination:
    mov [tmp_chain_count], eax
.clear_destination:
    mov eax, [tmp_mv_new_parent]
    mov ebx, [tmp_new_entry_idx]
    call fs_clear_entry_in_dir
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_chain_count]
    ret

.refresh_cwd:
    cmp byte [tmp_cwd_affected], 1
    jne .success
    call fs_rebuild_cwd_path
    cmp eax, FS_OK
    jl .done

.success:
    mov eax, FS_OK
    ret
.exists:
    mov eax, FS_ERR_EXISTS
    ret
.invalid:
    mov eax, FS_ERR_INVALID
.done:
    ret
