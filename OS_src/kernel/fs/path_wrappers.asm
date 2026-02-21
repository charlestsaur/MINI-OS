; ----------------------------
; Path wrappers used by shell
; ----------------------------
; IN: ESI=path
; OUT: EAX=inode or -1
fs_lookup_path:
    call fs_resolve_path
    ret

; IN: ESI=path
; OUT: EAX=0 ok, -1 nf, -2 not dir
fs_change_dir_path:
    call fs_resolve_path
    cmp eax, -1
    je .nf

    mov [tmp_inode_idx], eax
    mov edi, BUF_INODE
    call fs_read_inode
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .nd

    mov eax, [tmp_inode_idx]
    mov [cwd_inode], eax
    call fs_rebuild_cwd_path
    xor eax, eax
    ret

.nf:
    mov eax, -1
    ret

.nd:
    mov eax, -2
    ret

; IN: ESI=path
; OUT: EAX=0 ok, negative error
fs_create_file_path:
    call fs_split_parent_name
    cmp eax, -1
    jne .go
    mov eax, -4
    ret
.go:
    call fs_create_file_in_dir
    ret

; IN: ESI=path
; OUT: EAX=0 ok, negative error
fs_create_dir_path:
    call fs_split_parent_name
    cmp eax, -1
    jne .go
    mov eax, -4
    ret
.go:
    call fs_create_dir_in_dir
    ret

; IN: ESI=path
; OUT: EAX=0 ok, -1 nf, -2 dir not empty, -3 root deny
fs_remove_path:
    call fs_split_parent_name
    cmp eax, -1
    jne .go
    mov eax, -1
    ret
.go:
    call fs_remove_entry_in_dir
    ret

; IN: ESI=old path, EDI=new path
; OUT: EAX=0 ok, negative error
fs_rename_path:
    mov [tmp_mv_old_path], esi
    mov [tmp_mv_new_path], edi

    mov esi, [tmp_mv_old_path]
    call fs_split_parent_name
    cmp eax, -1
    je .nf
    mov [tmp_mv_old_parent], eax

    mov esi, PATH_NAME_BUF
    mov edi, PATH_PART_BUF
    call copy_string

    mov esi, [tmp_mv_new_path]
    call fs_split_parent_name
    cmp eax, -1
    je .nf
    mov [tmp_mv_new_parent], eax

    mov eax, [tmp_mv_old_parent]
    cmp eax, [tmp_mv_new_parent]
    jne .lookup_old
    mov esi, PATH_PART_BUF
    mov edi, PATH_NAME_BUF
    call str_eq_ci
    cmp al, 1
    je .ok

.lookup_old:
    mov eax, [tmp_mv_old_parent]
    mov esi, PATH_PART_BUF
    call fs_find_entry_in_dir
    cmp eax, -1
    je .nf
    mov [tmp_child_inode], eax
    mov [tmp_entry_idx], ebx
    mov [tmp_type], dl

    mov eax, [tmp_mv_new_parent]
    mov esi, PATH_NAME_BUF
    call fs_find_entry_in_dir
    cmp eax, -1
    jne .exists

    cmp byte [tmp_type], 2
    jne .write_new_entry
    mov eax, [tmp_mv_new_parent]
    mov ebx, [tmp_child_inode]
    call fs_parent_contains_inode
    cmp al, 1
    je .invalid

.write_new_entry:
    mov eax, [tmp_mv_new_parent]
    call fs_find_free_entry_in_dir
    cmp eax, -1
    je .nf
    mov [tmp_data_lba], ebx

    mov eax, [tmp_mv_new_parent]
    mov ebx, [tmp_data_lba]
    mov ecx, [tmp_child_inode]
    mov dl, [tmp_type]
    mov esi, PATH_NAME_BUF
    call fs_write_entry_in_dir
    cmp eax, -1
    je .nf

    mov eax, [tmp_mv_old_parent]
    mov ebx, [tmp_entry_idx]
    call fs_clear_entry_in_dir

    mov eax, [tmp_child_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    mov edi, BUF_INODE + INODE_NAME_OFF
    mov esi, PATH_NAME_BUF
    call copy_name_27
    mov eax, [tmp_mv_new_parent]
    mov [BUF_INODE + INODE_PARENT_OFF], eax
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode

.ok:
    xor eax, eax
    ret

.nf:
    mov eax, -1
    ret

.exists:
    mov eax, -2
    ret

.invalid:
    mov eax, -3
    ret
