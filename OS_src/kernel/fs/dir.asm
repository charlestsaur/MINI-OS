; ----------------------------
; Directory primitives
; ----------------------------
; IN: EAX=dir inode
; OUT: EAX=start lba, ECX=blocks, -1 on failure
fs_get_dir_info:
    push ebx
    push edi
    mov edi, BUF_INODE
    call fs_read_inode
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .bad
    mov ecx, [BUF_INODE + INODE_BLOCKS_OFF]
    cmp ecx, 0
    je .bad
    cmp ecx, FS_DATA_BLOCK_COUNT
    jg .bad
    mov eax, [BUF_INODE + INODE_START_OFF]
    cmp eax, FS_DATA_START_LBA
    jl .bad
    mov edx, eax
    add edx, ecx
    jc .bad
    mov ebx, FS_DATA_START_LBA + FS_DATA_BLOCK_COUNT
    cmp edx, ebx
    jg .bad
    pop edi
    pop ebx
    ret
.bad:
    mov eax, -1
    pop edi
    pop ebx
    ret

; IN: EAX=dir inode, ESI=name
; OUT: EAX=inode idx or -1; EBX=entry index; DL=type
fs_find_entry_in_dir:
    push ecx
    push edx
    push ebp
    push edi

    mov [tmp_name_ptr], esi

    call fs_get_dir_info
    cmp eax, -1
    je .fail

    mov [tmp_data_lba], eax
    mov [tmp_inode_idx], ecx

    xor edx, edx                        ; block index
.block_loop:
    cmp edx, [tmp_inode_idx]
    jge .fail

    mov eax, [tmp_data_lba]
    add eax, edx
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28

    xor ecx, ecx                        ; slot index
.slot_loop:
    cmp ecx, DIR_ENTRIES_PER_BLK
    jge .next_block

    mov ebx, ecx
    shl ebx, 5
    cmp dword [BUF_SECTOR + ebx + DIR_ENTRY_INODE_OFF], 0
    je .next_slot

    mov esi, [tmp_name_ptr]
    lea edi, [BUF_SECTOR + ebx + DIR_ENTRY_NAME_OFF]
    call name_field_eq_input
    cmp al, 1
    je .found

.next_slot:
    inc ecx
    jmp .slot_loop

.next_block:
    inc edx
    jmp .block_loop

.found:
    mov ebp, ebx
    shr ebp, 5
    mov ebx, edx
    shl ebx, 4
    add ebx, ebp
    shl ebp, 5
    mov eax, [BUF_SECTOR + ebp + DIR_ENTRY_INODE_OFF]
    mov dl, [BUF_SECTOR + ebp + DIR_ENTRY_TYPE_OFF]
    mov [tmp_type], dl
    pop edi
    pop ebp
    pop edx
    pop ecx
    mov dl, [tmp_type]
    ret

.fail:
    mov eax, -1
    pop edi
    pop ebp
    pop edx
    pop ecx
    ret

; IN: EAX=dir inode
; OUT: EAX=0 success; EBX=entry index; -1 no space
fs_find_free_entry_in_dir:
    push ecx
    push edx
    push esi
    push edi

    mov [tmp_parent_inode], eax

    call fs_get_dir_info
    cmp eax, -1
    je .fail

    mov [tmp_data_lba], eax
    mov [tmp_inode_idx], ecx

    xor edx, edx
.scan_block:
    cmp edx, [tmp_inode_idx]
    jge .expand

    mov eax, [tmp_data_lba]
    add eax, edx
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28

    xor ecx, ecx
.scan_slot:
    cmp ecx, DIR_ENTRIES_PER_BLK
    jge .next_block
    mov ebx, ecx
    shl ebx, 5
    cmp dword [BUF_SECTOR + ebx + DIR_ENTRY_INODE_OFF], 0
    je .found
    inc ecx
    jmp .scan_slot

.next_block:
    inc edx
    jmp .scan_block

.expand:
    ; Extend directory by one contiguous block.
    mov eax, [tmp_data_lba]
    add eax, [tmp_inode_idx]
    mov [tmp_data_lba], eax

    mov ebx, eax
    sub ebx, FS_DATA_START_LBA
    call fs_alloc_data_block_index
    cmp eax, -1
    je .fail

    mov edi, BUF_SECTOR
    call zero_sector
    mov eax, [tmp_data_lba]
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28

    mov eax, [tmp_parent_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    inc dword [BUF_INODE + INODE_BLOCKS_OFF]
    mov eax, [tmp_parent_inode]
    mov esi, BUF_INODE
    call fs_write_inode

    mov ebx, [tmp_inode_idx]
    shl ebx, 4
    xor eax, eax
    pop edi
    pop esi
    pop edx
    pop ecx
    ret

.found:
    mov ebx, edx
    shl ebx, 4
    add ebx, ecx
    xor eax, eax
    pop edi
    pop esi
    pop edx
    pop ecx
    ret

.fail:
    mov eax, -1
    pop edi
    pop esi
    pop edx
    pop ecx
    ret

; IN: EAX=dir inode, EBX=entry index, ECX=child inode, DL=type, ESI=name
; OUT: EAX=0 or -1
fs_write_entry_in_dir:
    push ebp
    push ecx
    push edx
    push esi
    push edi

    mov [tmp_parent_inode], eax
    mov [tmp_inode_idx], ecx
    mov [tmp_type], dl
    mov [tmp_name_ptr], esi

    call fs_get_dir_info
    cmp eax, -1
    je .fail

    mov ebp, ebx
    shr ebp, 4
    and ebx, 0x0F

    add eax, ebp
    mov [tmp_data_lba], eax
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28

    shl ebx, 5
    mov ecx, [tmp_inode_idx]
    mov [BUF_SECTOR + ebx + DIR_ENTRY_INODE_OFF], ecx
    mov dl, [tmp_type]
    mov [BUF_SECTOR + ebx + DIR_ENTRY_TYPE_OFF], dl
    lea edi, [BUF_SECTOR + ebx + DIR_ENTRY_NAME_OFF]
    mov esi, [tmp_name_ptr]
    call copy_name_27

    mov eax, [tmp_data_lba]
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28

    xor eax, eax
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebp
    ret

.fail:
    mov eax, -1
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebp
    ret

; IN: EAX=dir inode, EBX=entry index
; OUT: EAX=0 or -1
fs_clear_entry_in_dir:
    push ebp
    push ecx
    push esi
    push edi

    mov [tmp_parent_inode], eax

    call fs_get_dir_info
    cmp eax, -1
    je .fail

    mov ebp, ebx
    shr ebp, 4
    and ebx, 0x0F

    add eax, ebp
    mov [tmp_data_lba], eax
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28

    shl ebx, 5
    lea edi, [BUF_SECTOR + ebx]
    mov ecx, DIR_ENTRY_SIZE
    call zero_buffer

    mov eax, [tmp_data_lba]
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28

    xor eax, eax
    pop edi
    pop esi
    pop ecx
    pop ebp
    ret

.fail:
    mov eax, -1
    pop edi
    pop esi
    pop ecx
    pop ebp
    ret
