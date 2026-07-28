; ----------------------------
; High-level directory-scoped operations
; ----------------------------

; IN: EBX=inode index
; OUT: EAX=FS_OK or a filesystem error
fs_release_inode_record:
    push ebx
    push ecx
    push esi
    push edi

    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov eax, ebx
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .done
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_clear

.done:
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

; IN: EAX=parent directory inode, ESI=name
; OUT: EAX=created inode or a filesystem error
fs_create_file_in_dir:
    push ebx
    push ecx

    mov [tmp_parent_inode], eax
    mov [tmp_name_ptr], esi
    call fs_get_dir_info
    cmp eax, FS_OK
    jl .done
    mov esi, [tmp_name_ptr]
    call fs_validate_name
    cmp eax, FS_OK
    jl .done

    mov eax, [tmp_parent_inode]
    mov esi, [tmp_name_ptr]
    call fs_find_entry_in_dir
    cmp eax, FS_ERR_NOT_FOUND
    je .allocate
    cmp eax, FS_OK
    jl .done
    mov eax, FS_ERR_EXISTS
    jmp .done

.allocate:
    call fs_alloc_inode
    cmp eax, FS_OK
    jl .done
    mov [tmp_child_inode], eax

    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov byte [BUF_INODE + INODE_TYPE_OFF], 1
    mov esi, [tmp_name_ptr]
    mov edi, BUF_INODE + INODE_NAME_OFF
    call copy_name_27
    mov eax, [tmp_parent_inode]
    mov [BUF_INODE + INODE_PARENT_OFF], eax
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .rollback_inode

    mov eax, [tmp_parent_inode]
    call fs_find_free_entry_in_dir
    cmp eax, FS_OK
    jl .rollback_inode
    mov [tmp_entry_idx], ebx

    mov eax, [tmp_parent_inode]
    mov ebx, [tmp_entry_idx]
    mov ecx, [tmp_child_inode]
    mov dl, 1
    mov esi, [tmp_name_ptr]
    call fs_write_entry_in_dir
    cmp eax, FS_OK
    jl .rollback_inode

    mov eax, [tmp_child_inode]
    jmp .done

.rollback_inode:
    mov [tmp_chain_count], eax
    mov ebx, [tmp_child_inode]
    call fs_release_inode_record
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_chain_count]
.done:
    pop ecx
    pop ebx
    ret

; IN: EAX=parent directory inode, ESI=name
; OUT: EAX=FS_OK or a filesystem error
fs_create_dir_in_dir:
    push ebx
    push ecx

    mov [tmp_parent_inode], eax
    mov [tmp_name_ptr], esi
    call fs_get_dir_info
    cmp eax, FS_OK
    jl .done
    mov esi, [tmp_name_ptr]
    call fs_validate_name
    cmp eax, FS_OK
    jl .done

    mov eax, [tmp_parent_inode]
    mov esi, [tmp_name_ptr]
    call fs_find_entry_in_dir
    cmp eax, FS_ERR_NOT_FOUND
    je .allocate
    cmp eax, FS_OK
    jl .done
    mov eax, FS_ERR_EXISTS
    jmp .done

.allocate:
    call fs_alloc_inode
    cmp eax, FS_OK
    jl .done
    mov [tmp_child_inode], eax
    call fs_fat_alloc_block
    cmp eax, FS_OK
    jl .rollback_inode_only
    mov [tmp_child_data_lba], eax

    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov byte [BUF_INODE + INODE_TYPE_OFF], 2
    mov esi, [tmp_name_ptr]
    mov edi, BUF_INODE + INODE_NAME_OFF
    call copy_name_27
    mov eax, [tmp_child_data_lba]
    mov [BUF_INODE + INODE_START_OFF], eax
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    mov eax, [tmp_parent_inode]
    mov [BUF_INODE + INODE_PARENT_OFF], eax
    mov eax, [tmp_child_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .rollback_all

    mov eax, [tmp_parent_inode]
    call fs_find_free_entry_in_dir
    cmp eax, FS_OK
    jl .rollback_all
    mov [tmp_entry_idx], ebx

    mov eax, [tmp_parent_inode]
    mov ebx, [tmp_entry_idx]
    mov ecx, [tmp_child_inode]
    mov dl, 2
    mov esi, [tmp_name_ptr]
    call fs_write_entry_in_dir
    cmp eax, FS_OK
    jl .rollback_all
    mov eax, FS_OK
    jmp .done

.rollback_all:
    mov [tmp_chain_count], eax
    mov eax, [tmp_child_data_lba]
    mov ecx, 1
    call fs_fat_free_chain
    cmp eax, FS_OK
    jl .done
    mov ebx, [tmp_child_inode]
    call fs_release_inode_record
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_chain_count]
    jmp .done

.rollback_inode_only:
    mov [tmp_chain_count], eax
    mov ebx, [tmp_child_inode]
    call fs_release_inode_record
    cmp eax, FS_OK
    jl .done
    mov eax, [tmp_chain_count]
.done:
    pop ecx
    pop ebx
    ret

; IN: EDI=inode buffer
; OUT: EAX=FS_OK or a filesystem error
fs_free_inode_data_blocks:
    mov ecx, [edi + INODE_BLOCKS_OFF]
    cmp ecx, FS_DATA_BLOCK_COUNT
    ja .corrupt
    mov eax, [edi + INODE_START_OFF]
    call fs_fat_free_chain
    ret
.corrupt:
    mov eax, FS_ERR_CORRUPT
    ret

; IN: EAX=directory inode
; OUT: EAX=1 empty, 0 non-empty, or a filesystem error
fs_is_dir_empty:
    push ebx
    push ecx
    push edx
    push ebp
    push edi

    call fs_get_dir_info
    cmp eax, FS_OK
    jl .done
    mov [tmp_chain_block], eax
    mov [tmp_chain_count], ecx
    xor ebp, ebp

.block_loop:
    cmp ebp, [tmp_chain_count]
    jae .empty
    mov eax, [tmp_chain_block]
    mov ebx, ebp
    mov ecx, [tmp_chain_count]
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl .done

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
    jne .not_empty
    inc ecx
    jmp .slot_loop

.next_block:
    inc ebp
    jmp .block_loop
.empty:
    mov eax, 1
    jmp .done
.not_empty:
    xor eax, eax
    jmp .done
.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop ebp
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=parent directory inode, ESI=name
; OUT: EAX=FS_OK or a filesystem error
fs_remove_entry_in_dir:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov [tmp_parent_inode], eax
    mov [tmp_name_ptr], esi
    call fs_find_entry_in_dir
    cmp eax, FS_OK
    jl .done
    mov [tmp_child_inode], eax
    mov [tmp_entry_idx], ebx
    mov [tmp_type], dl

    cmp eax, 0
    je .protected
    cmp byte [tmp_type], 2
    jne .read_child

    mov eax, [cwd_inode]
    mov ebx, [tmp_child_inode]
    call fs_parent_contains_inode
    cmp eax, FS_OK
    jl .done
    cmp eax, 1
    je .protected

    mov eax, [tmp_child_inode]
    call fs_is_dir_empty
    cmp eax, FS_OK
    jl .done
    cmp eax, 1
    jne .not_empty

.read_child:
    mov eax, [tmp_child_inode]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    mov al, [BUF_INODE + INODE_TYPE_OFF]
    cmp al, [tmp_type]
    jne .corrupt
    mov eax, [BUF_INODE + INODE_START_OFF]
    mov [tmp_chain_block], eax
    mov eax, [BUF_INODE + INODE_BLOCKS_OFF]
    mov [tmp_chain_count], eax

    ; The name becomes unreachable before its storage can be reused.
    mov eax, [tmp_parent_inode]
    mov ebx, [tmp_entry_idx]
    call fs_clear_entry_in_dir
    cmp eax, FS_OK
    jl .done

    cmp dword [tmp_chain_count], 0
    je .clear_inode
    mov eax, [tmp_chain_block]
    mov ecx, [tmp_chain_count]
    call fs_fat_free_chain
    cmp eax, FS_OK
    jl .done

.clear_inode:
    mov ebx, [tmp_child_inode]
    call fs_release_inode_record
    jmp .done

.not_empty:
    mov eax, FS_ERR_NOT_EMPTY
    jmp .done
.protected:
    mov eax, FS_ERR_PROTECTED
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=candidate inode, EBX=target ancestor
; OUT: EAX=1 if candidate is target/inside target, 0 otherwise, or error
fs_parent_contains_inode:
    push ebx
    push ecx
    push edx
    push edi

    mov edx, eax
    call fs_chain_reset
    mov ecx, FS_INODE_COUNT
.loop:
    cmp edx, ebx
    je .yes
    cmp edx, 0
    je .no
    cmp ecx, 0
    je .corrupt

    mov eax, edx
    call fs_path_visit_inode
    cmp eax, FS_OK
    jl .done
    mov eax, edx
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .corrupt
    mov edx, [BUF_INODE + INODE_PARENT_OFF]
    cmp edx, FS_INODE_COUNT
    jae .corrupt
    dec ecx
    jmp .loop

.yes:
    mov eax, 1
    jmp .done
.no:
    xor eax, eax
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret
