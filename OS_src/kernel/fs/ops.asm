; ----------------------------
; High-level operations (directory-scoped)
; ----------------------------
; IN: EAX=parent dir inode, ESI=name
; OUT: EAX=0 ok, -1 exists, -2 no inode, -3 no slot, -4 invalid
fs_create_file_in_dir:
    push ebx
    push ecx

    mov [tmp_parent_inode], eax
    mov [tmp_new_parent], esi

    mov eax, [tmp_parent_inode]
    call fs_get_dir_info
    cmp eax, -1
    je .invalid

    mov esi, [tmp_new_parent]
    call fs_validate_name
    cmp al, 1
    jne .invalid

    mov eax, [tmp_parent_inode]
    mov esi, [tmp_new_parent]
    call fs_find_entry_in_dir
    cmp eax, -1
    jne .exists

    call fs_alloc_inode
    cmp eax, -1
    je .no_inode
    mov [tmp_child_inode], eax

    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov byte [BUF_INODE + INODE_TYPE_OFF], 1
    mov esi, [tmp_new_parent]
    mov edi, BUF_INODE + INODE_NAME_OFF
    call copy_name_27
    mov dword [BUF_INODE + INODE_SIZE_OFF], 0
    mov dword [BUF_INODE + INODE_START_OFF], 0
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 0
    mov eax, [tmp_parent_inode]
    mov [BUF_INODE + INODE_PARENT_OFF], eax

    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode

    mov eax, [tmp_parent_inode]
    call fs_find_free_entry_in_dir
    cmp eax, -1
    je .no_slot

    mov eax, [tmp_parent_inode]
    mov ecx, [tmp_child_inode]
    mov dl, 1
    mov esi, [tmp_new_parent]
    call fs_write_entry_in_dir
    cmp eax, 0
    jne .write_fail

    xor eax, eax
    pop ecx
    pop ebx
    ret

.exists:
    mov eax, -1
    pop ecx
    pop ebx
    ret

.no_inode:
    mov eax, -2
    pop ecx
    pop ebx
    ret

.no_slot:
    mov ebx, [tmp_child_inode]
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_clear
    mov eax, -3
    pop ecx
    pop ebx
    ret

.write_fail:
    mov ebx, [tmp_child_inode]
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_clear
    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    mov eax, -3
    pop ecx
    pop ebx
    ret

.invalid:
    mov eax, -4
    pop ecx
    pop ebx
    ret

; IN: EAX=parent dir inode, ESI=name
; OUT: EAX=0 ok, -1 exists, -2 no inode, -3 no data, -4 no slot/name
fs_create_dir_in_dir:
    push ebx
    push ecx

    mov [tmp_parent_inode], eax
    mov [tmp_new_parent], esi

    mov eax, [tmp_parent_inode]
    call fs_get_dir_info
    cmp eax, -1
    je .invalid

    mov esi, [tmp_new_parent]
    call fs_validate_name
    cmp al, 1
    jne .invalid

    mov eax, [tmp_parent_inode]
    mov esi, [tmp_new_parent]
    call fs_find_entry_in_dir
    cmp eax, -1
    jne .exists

    call fs_alloc_inode
    cmp eax, -1
    je .no_inode
    mov [tmp_child_inode], eax

    call fs_alloc_data_block
    cmp eax, -1
    je .no_data
    mov [tmp_child_data_lba], eax

    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov byte [BUF_INODE + INODE_TYPE_OFF], 2
    mov esi, [tmp_new_parent]
    mov edi, BUF_INODE + INODE_NAME_OFF
    call copy_name_27
    mov dword [BUF_INODE + INODE_SIZE_OFF], 0
    mov eax, [tmp_child_data_lba]
    mov [BUF_INODE + INODE_START_OFF], eax
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    mov eax, [tmp_parent_inode]
    mov [BUF_INODE + INODE_PARENT_OFF], eax

    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode

    mov edi, BUF_SECTOR
    call zero_sector
    mov eax, [tmp_child_data_lba]
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28

    mov eax, [tmp_parent_inode]
    call fs_find_free_entry_in_dir
    cmp eax, -1
    je .no_slot

    mov eax, [tmp_parent_inode]
    mov ecx, [tmp_child_inode]
    mov dl, 2
    mov esi, [tmp_new_parent]
    call fs_write_entry_in_dir
    cmp eax, 0
    jne .write_fail

    xor eax, eax
    pop ecx
    pop ebx
    ret

.exists:
    mov eax, -1
    pop ecx
    pop ebx
    ret

.no_inode:
    mov eax, -2
    pop ecx
    pop ebx
    ret

.no_data:
    mov ebx, [tmp_child_inode]
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_clear
    mov eax, -3
    pop ecx
    pop ebx
    ret

.no_slot:
    mov ebx, [tmp_child_inode]
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_clear
    mov eax, [tmp_child_data_lba]
    call fs_free_data_block_lba
    mov eax, -4
    pop ecx
    pop ebx
    ret

.write_fail:
    mov ebx, [tmp_child_inode]
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_clear
    mov eax, [tmp_child_data_lba]
    call fs_free_data_block_lba
    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    mov eax, -4
    pop ecx
    pop ebx
    ret

.invalid:
    mov eax, -4
    pop ecx
    pop ebx
    ret

; IN: EDI=inode buffer (must contain inode)
fs_free_inode_data_blocks:
    push eax
    push ebx
    push ecx

    mov ecx, [edi + INODE_BLOCKS_OFF]
    cmp ecx, 0
    je .done

    mov eax, [edi + INODE_START_OFF]
.loop:
    call fs_free_data_block_lba
    inc eax
    dec ecx
    jnz .loop

.done:
    pop ecx
    pop ebx
    pop eax
    ret

; IN: EAX=dir inode
; OUT: AL=1 empty, 0 not empty/invalid
fs_is_dir_empty:
    push ebx
    push ecx
    push edx
    push edi

    call fs_get_dir_info
    cmp eax, -1
    je .not_empty

    mov [tmp_data_lba], eax
    mov [tmp_inode_idx], ecx

    xor edx, edx
.block_loop:
    cmp edx, [tmp_inode_idx]
    jge .empty

    mov eax, [tmp_data_lba]
    add eax, edx
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28

    xor ecx, ecx
.slot_loop:
    cmp ecx, DIR_ENTRIES_PER_BLK
    jge .next_block

    mov ebx, ecx
    shl ebx, 5
    cmp dword [BUF_SECTOR + ebx + DIR_ENTRY_INODE_OFF], 0
    jne .not_empty
    inc ecx
    jmp .slot_loop

.next_block:
    inc edx
    jmp .block_loop

.empty:
    mov al, 1
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

.not_empty:
    xor al, al
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=parent dir inode, ESI=name
; OUT: EAX=0 ok, -1 missing, -2 not empty, -3 root deny
fs_remove_entry_in_dir:
    push ebx

    mov [tmp_parent_inode], eax
    call fs_find_entry_in_dir
    cmp eax, -1
    je .nf

    mov [tmp_child_inode], eax
    mov [tmp_entry_idx], ebx
    mov [tmp_type], dl

    cmp byte [tmp_type], 2
    jne .remove_any

    cmp dword [tmp_child_inode], 0
    je .root_deny

    mov eax, [tmp_child_inode]
    call fs_is_dir_empty
    cmp al, 1
    jne .not_empty

.remove_any:
    mov edi, BUF_INODE
    mov eax, [tmp_child_inode]
    call fs_read_inode

    mov edi, BUF_INODE
    call fs_free_inode_data_blocks

    mov ebx, [tmp_child_inode]
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_clear

    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode

    mov eax, [tmp_parent_inode]
    mov ebx, [tmp_entry_idx]
    call fs_clear_entry_in_dir

    xor eax, eax
    pop ebx
    ret

.nf:
    mov eax, -1
    pop ebx
    ret

.not_empty:
    mov eax, -2
    pop ebx
    ret

.root_deny:
    mov eax, -3
    pop ebx
    ret

; IN: EAX=parent dir inode, ESI=old name, EDI=new name
; OUT: EAX=0 ok, -1 missing, -2 target exists
fs_rename_in_dir:
    push ebx

    mov [tmp_parent_inode], eax
    mov [tmp_name_ptr], esi
    mov [tmp_new_parent], edi

    mov esi, [tmp_new_parent]
    call fs_validate_name
    cmp al, 1
    jne .nf

    mov eax, [tmp_parent_inode]
    mov esi, [tmp_new_parent]
    call fs_find_entry_in_dir
    cmp eax, -1
    jne .exists

    mov eax, [tmp_parent_inode]
    mov esi, [tmp_name_ptr]
    call fs_find_entry_in_dir
    cmp eax, -1
    je .nf

    mov [tmp_child_inode], eax
    mov [tmp_entry_idx], ebx
    mov [tmp_type], dl

    mov eax, [tmp_parent_inode]
    mov ebx, [tmp_entry_idx]
    mov ecx, [tmp_child_inode]
    mov dl, [tmp_type]
    mov esi, [tmp_new_parent]
    call fs_write_entry_in_dir

    mov eax, [tmp_child_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    mov edi, BUF_INODE + INODE_NAME_OFF
    mov esi, [tmp_new_parent]
    call copy_name_27
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode

    xor eax, eax
    pop ebx
    ret

.nf:
    mov eax, -1
    pop ebx
    ret

.exists:
    mov eax, -2
    pop ebx
    ret

; IN: EAX=candidate parent inode, EBX=inode to test
; OUT: AL=1 if candidate is inode itself or inside its subtree, else 0
fs_parent_contains_inode:
    push ecx
    push edi

    mov ecx, FS_INODE_COUNT
.loop:
    cmp eax, ebx
    je .yes
    cmp eax, 0
    je .no
    cmp ecx, 0
    je .yes

    mov edi, BUF_INODE
    call fs_read_inode
    mov eax, [BUF_INODE + INODE_PARENT_OFF]
    dec ecx
    jmp .loop

.yes:
    mov al, 1
    pop edi
    pop ecx
    ret

.no:
    xor al, al
    pop edi
    pop ecx
    ret
