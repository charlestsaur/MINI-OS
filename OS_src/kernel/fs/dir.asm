; ----------------------------
; Directory primitives
; ----------------------------

; IN: EAX=directory inode
; OUT: EAX=start block, ECX=declared blocks, or a filesystem error
fs_get_dir_info:
    push ebx
    push edi

    mov ebx, eax
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .not_dir

    mov ecx, [BUF_INODE + INODE_BLOCKS_OFF]
    cmp ecx, 1
    jb .corrupt
    cmp ecx, FS_DATA_BLOCK_COUNT
    ja .corrupt

    mov eax, [BUF_INODE + INODE_START_OFF]
    cmp eax, 2
    jb .corrupt
    cmp eax, FS_DATA_BLOCK_COUNT
    jae .corrupt
    jmp .done

.not_dir:
    mov eax, FS_ERR_NOT_DIR
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop ebx
    ret

; IN: EAX=directory inode, ESI=name
; OUT: EAX=child inode or error; EBX=entry index; DL=type
fs_find_entry_in_dir:
    push ecx
    push edx
    push ebp
    push edi

    mov [tmp_name_ptr], esi
    call fs_get_dir_info
    cmp eax, FS_OK
    jl .done

    mov ebx, eax
    mov [tmp_chain_count], ecx
    xor ebp, ebp
    call fs_chain_reset

.block_loop:
    cmp dword [tmp_chain_count], 0
    je .corrupt
    mov eax, ebx
    call fs_chain_visit_block
    cmp eax, FS_OK
    jl .done

    mov eax, ebx
    add eax, FS_DATA_START_LBA
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    jc .io

    xor ecx, ecx
.slot_loop:
    cmp ecx, DIR_ENTRIES_PER_BLK
    jge .next_block
    mov edi, ecx
    shl edi, 5
    cmp dword [BUF_SECTOR + edi + DIR_ENTRY_INODE_OFF], 0
    je .next_slot

    push esi
    mov esi, [tmp_name_ptr]
    add edi, BUF_SECTOR + DIR_ENTRY_NAME_OFF
    call name_field_eq_input
    pop esi
    cmp al, 1
    je .found

.next_slot:
    inc ecx
    jmp .slot_loop

.next_block:
    dec dword [tmp_chain_count]
    mov eax, ebx
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    cmp dword [tmp_chain_count], 0
    je .expect_eoc
    cmp eax, FS_FAT_EOC
    je .corrupt
    mov ebx, eax
    inc ebp
    jmp .block_loop

.expect_eoc:
    cmp eax, FS_FAT_EOC
    jne .corrupt
    mov eax, FS_ERR_NOT_FOUND
    jmp .done

.found:
    mov edi, ecx
    shl edi, 5
    mov eax, [BUF_SECTOR + edi + DIR_ENTRY_INODE_OFF]
    cmp eax, 1
    jb .corrupt
    cmp eax, FS_INODE_COUNT
    jae .corrupt
    mov dl, [BUF_SECTOR + edi + DIR_ENTRY_TYPE_OFF]
    cmp dl, 1
    je .type_ok
    cmp dl, 2
    jne .corrupt
.type_ok:
    mov [tmp_type], dl
    mov ebx, ebp
    shl ebx, 4
    add ebx, ecx
    mov dl, [tmp_type]
    jmp .done

.io:
    mov eax, FS_ERR_IO
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop ebp
    pop edx
    pop ecx
    cmp eax, FS_OK
    jl .return
    mov dl, [tmp_type]
.return:
    ret

; IN: EAX=directory inode
; OUT: EAX=FS_OK or error; EBX=free entry index
fs_find_free_entry_in_dir:
    push ecx
    push edx
    push ebp
    push esi
    push edi

    mov [tmp_parent_inode], eax
    call fs_get_dir_info
    cmp eax, FS_OK
    jl .done

    mov ebx, eax
    mov [tmp_chain_count], ecx
    xor ebp, ebp
    call fs_chain_reset

.block_loop:
    cmp dword [tmp_chain_count], 0
    je .corrupt
    mov eax, ebx
    call fs_chain_visit_block
    cmp eax, FS_OK
    jl .done
    mov [tmp_chain_block], ebx

    mov eax, ebx
    add eax, FS_DATA_START_LBA
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    jc .io

    xor ecx, ecx
.slot_loop:
    cmp ecx, DIR_ENTRIES_PER_BLK
    jge .next_block
    mov edx, ecx
    shl edx, 5
    cmp dword [BUF_SECTOR + edx + DIR_ENTRY_INODE_OFF], 0
    je .found
    inc ecx
    jmp .slot_loop

.next_block:
    dec dword [tmp_chain_count]
    mov eax, ebx
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    cmp dword [tmp_chain_count], 0
    je .expect_eoc
    cmp eax, FS_FAT_EOC
    je .corrupt
    mov ebx, eax
    inc ebp
    jmp .block_loop

.expect_eoc:
    cmp eax, FS_FAT_EOC
    jne .corrupt
    jmp .expand

.found:
    mov ebx, ebp
    shl ebx, 4
    add ebx, ecx
    mov eax, FS_OK
    jmp .done

.expand:
    call fs_fat_alloc_block
    cmp eax, FS_OK
    jl .done
    mov [tmp_chain_next], eax

    mov ebx, eax
    mov eax, [tmp_chain_block]
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .free_unlinked

    mov eax, [tmp_parent_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .rollback_link
    mov eax, ebp
    inc eax
    cmp [BUF_INODE + INODE_BLOCKS_OFF], eax
    jne .rollback_corrupt
    inc dword [BUF_INODE + INODE_BLOCKS_OFF]
    mov eax, [tmp_parent_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .rollback_link

    inc ebp
    mov ebx, ebp
    shl ebx, 4
    mov eax, FS_OK
    jmp .done

.rollback_corrupt:
    mov dword [tmp_chain_count], FS_ERR_CORRUPT
    jmp .rollback
.rollback_link:
    mov [tmp_chain_count], eax
.rollback:
    mov eax, [tmp_chain_block]
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .io
    mov eax, [tmp_chain_next]
    mov ecx, 1
    call fs_fat_free_chain
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_chain_count]
    jmp .done

.free_unlinked:
    mov [tmp_chain_count], eax
    ; A failed FAT-sector write is ambiguous.  Restore the old EOC before
    ; releasing the new block so a possibly committed link never dangles.
    mov eax, [tmp_chain_block]
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .io
    mov eax, [tmp_chain_next]
    mov ecx, 1
    call fs_fat_free_chain
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_chain_count]
    jmp .done

.io:
    mov eax, FS_ERR_IO
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop esi
    pop ebp
    pop edx
    pop ecx
    ret

; IN: EAX=directory inode, EBX=entry index, ECX=child inode,
;     DL=type, ESI=name
; OUT: EAX=FS_OK or a filesystem error
fs_write_entry_in_dir:
    push ebx
    push ecx
    push edx
    push ebp
    push esi
    push edi

    mov [tmp_parent_inode], eax
    mov [tmp_entry_idx], ebx
    mov [tmp_inode_idx], ecx
    mov [tmp_type], dl
    mov [tmp_name_ptr], esi

    cmp ecx, 1
    jb .corrupt
    cmp ecx, FS_INODE_COUNT
    jae .corrupt
    cmp dl, 1
    je .params_ok
    cmp dl, 2
    jne .corrupt

.params_ok:
    call fs_get_dir_info
    cmp eax, FS_OK
    jl .done
    mov ebp, [tmp_entry_idx]
    shr ebp, 4
    mov ebx, ebp
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl .done

    add eax, FS_DATA_START_LBA
    mov [tmp_data_lba], eax
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    jc .io

    mov ebx, [tmp_entry_idx]
    and ebx, 0x0F
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
    jc .io
    mov eax, FS_OK
    jmp .done

.io:
    mov eax, FS_ERR_IO
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

; IN: EAX=directory inode, EBX=entry index
; OUT: EAX=FS_OK or a filesystem error
fs_clear_entry_in_dir:
    push ebx
    push ecx
    push ebp
    push esi
    push edi

    mov [tmp_parent_inode], eax
    mov [tmp_entry_idx], ebx
    call fs_get_dir_info
    cmp eax, FS_OK
    jl .done

    mov ebp, [tmp_entry_idx]
    shr ebp, 4
    mov ebx, ebp
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl .done

    add eax, FS_DATA_START_LBA
    mov [tmp_data_lba], eax
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    jc .io

    mov ebx, [tmp_entry_idx]
    and ebx, 0x0F
    shl ebx, 5
    lea edi, [BUF_SECTOR + ebx]
    mov ecx, DIR_ENTRY_SIZE
    call zero_buffer

    mov eax, [tmp_data_lba]
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    jc .io
    mov eax, FS_OK
    jmp .done

.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop esi
    pop ebp
    pop ecx
    pop ebx
    ret
