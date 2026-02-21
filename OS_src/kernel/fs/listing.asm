; ----------------------------
; Listing
; ----------------------------
fs_list_cwd:
    mov esi, msg_ls
    call vga_print

    mov eax, [cwd_inode]
    call fs_get_dir_info
    cmp eax, -1
    je .done

    mov [tmp_data_lba], eax
    mov [tmp_inode_idx], ecx

    xor edx, edx
.block_loop:
    cmp edx, [tmp_inode_idx]
    jge .done

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
    mov eax, [BUF_SECTOR + ebx + DIR_ENTRY_INODE_OFF]
    cmp eax, 0
    je .next_slot

    mov al, [BUF_SECTOR + ebx + DIR_ENTRY_TYPE_OFF]
    cmp al, 1
    je .print_entry
    cmp al, 2
    jne .next_slot

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
    inc edx
    jmp .block_loop

.done:
    ret
