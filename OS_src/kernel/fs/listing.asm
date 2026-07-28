; ----------------------------
; Directory listing
; ----------------------------

; OUT: EAX=FS_OK or a filesystem error
fs_list_cwd:
    push ebx
    push ecx
    push ebp
    push esi
    push edi

    mov esi, msg_ls
    call vga_print
    mov eax, [cwd_inode]
    call fs_get_dir_info
    cmp eax, FS_OK
    jl .done

    mov [tmp_chain_block], eax
    mov [tmp_chain_count], ecx
    xor ebp, ebp

.block_loop:
    cmp ebp, [tmp_chain_count]
    jae .success
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
    mov ebx, ecx
    shl ebx, 5
    mov eax, [BUF_SECTOR + ebx + DIR_ENTRY_INODE_OFF]
    test eax, eax
    jz .next_slot

    mov al, [BUF_SECTOR + ebx + DIR_ENTRY_TYPE_OFF]
    cmp al, 1
    je .print_entry
    cmp al, 2
    jne .corrupt

.print_entry:
    mov esi, msg_file_prefix
    call vga_print
    lea esi, [BUF_SECTOR + ebx + DIR_ENTRY_NAME_OFF]
    call vga_print_name
    mov al, ' '
    call vga_putc
    mov al, '('
    call vga_putc
    mov al, [BUF_SECTOR + ebx + DIR_ENTRY_TYPE_OFF]
    cmp al, 2
    jne .file
    mov al, 'd'
    call vga_putc
    jmp .close
.file:
    mov al, 'f'
    call vga_putc
.close:
    mov al, ')'
    call vga_putc
    call vga_newline

.next_slot:
    inc ecx
    jmp .slot_loop

.next_block:
    inc ebp
    jmp .block_loop

.success:
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
    pop ecx
    pop ebx
    ret
