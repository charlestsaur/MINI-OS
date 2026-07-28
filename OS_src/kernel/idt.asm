[bits 32]

; ----------------------------
; IDT & System Call Module
; ----------------------------
IDT_BASE equ 0x26000

idt_descriptor:
    dw (256 * 8) - 1
    dd IDT_BASE

idt_init:
    push eax
    push ecx
    push edi

    ; Zero IDT memory at 0x26000 (2048 bytes)
    mov edi, IDT_BASE
    mov ecx, 256 * 8
    call zero_buffer

    ; Register int 0x80 (syscall) at entry 0x80 (128)
    mov edi, IDT_BASE + (0x80 * 8)
    mov eax, syscall_entry

    mov [edi], ax            ; Offset 0..15
    mov word [edi + 2], 0x08  ; Segment Selector (Code Segment)
    mov byte [edi + 4], 0    ; Reserved
    mov byte [edi + 5], 0xEE  ; Type_attr: Present, Ring 3, 32-bit Interrupt Gate
    shr eax, 16
    mov [edi + 6], ax        ; Offset 16..31

    lidt [idt_descriptor]

    pop edi
    pop ecx
    pop eax
    ret

; ----------------------------
; System Call Handler (int 0x80)
; ----------------------------
; EAX = syscall number (1=sys_exit, 3=sys_read, 4=sys_write)
; EBX = arg1 (exit_code / fd)
; ECX = arg2 (buf)
; EDX = arg3 (count)
syscall_entry:
    cmp eax, 1
    je near .sys_exit
    cmp eax, 3
    je near .sys_read
    cmp eax, 4
    je near .sys_write
    cmp eax, 5
    je near .sys_open
    cmp eax, 6
    je near .sys_close
    cmp eax, 7
    je near .sys_getkey
    cmp eax, 12
    je near .sys_brk

    cmp eax, 14
    je near .sys_read_file
    cmp eax, 15
    je near .sys_write_file
    cmp eax, 19
    je near .sys_lseek
    cmp eax, 20
    je near .sys_move_cursor
    cmp eax, 21
    je near .sys_clear_screen
    cmp eax, 22
    je near .sys_set_cursor_nosync
    cmp eax, 23
    je near .sys_save_screen
    cmp eax, 24
    je near .sys_restore_screen

    ; Unknown syscall -> iret
    iret

.sys_exit:
    mov byte [cursor_auto_sync], 1
    ; Reset file table slots 3..15
    mov ecx, 3

.clear_ft_loop:
    cmp ecx, 16
    jge .clear_ft_done
    mov eax, ecx
    shl eax, 4
    mov dword [file_table + eax], 0
    inc ecx
    jmp .clear_ft_loop
.clear_ft_done:

    ; Reset heap break pointer for next application run
    mov dword [current_brk], 0x00050000
    ; Restore Shell stack and return to Shell
    mov esp, [saved_kernel_esp]
    jmp strict dword return_to_shell

.sys_brk:
    test ebx, ebx
    jz .sys_brk_done

    cmp ebx, 0x00050000
    jb .sys_brk_done
    cmp ebx, 0x00080000
    ja .sys_brk_done

    mov [current_brk], ebx

.sys_brk_done:
    mov eax, [current_brk]
    iret

.sys_read:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov edi, ecx         ; Destination buffer
    xor esi, esi         ; Bytes read counter = 0

.sys_read_loop:
    cmp esi, edx         ; Reached max requested bytes?
    jge near .sys_read_done

    call kbd_read_char_blocking
    test al, al          ; Ignore 0 (key releases / unmapped keys)
    jz near .sys_read_loop

    cmp al, 13           ; Carriage return -> newline
    je near .sys_read_newline
    cmp al, 10           ; Line feed -> newline
    je near .sys_read_newline

    ; Check backspace (8)
    cmp al, 8
    jne near .sys_read_store_char

    ; Backspace pressed
    test esi, esi
    jz near .sys_read_loop    ; Nothing to backspace
    dec esi
    dec edi
    ; Echo backspace to VGA console (backspace, space, backspace)
    call vga_putc
    mov al, ' '
    call vga_putc
    mov al, 8
    call vga_putc
    jmp near .sys_read_loop

.sys_read_store_char:
    ; Store ASCII char in buffer
    mov [edi], al
    inc edi
    inc esi

    ; Echo character to VGA screen
    call vga_putc
    jmp near .sys_read_loop

.sys_read_newline:
    mov byte [edi], 0    ; Null-terminate string buffer
    mov al, 10
    call vga_putc        ; Echo newline

.sys_read_done:
    mov [tmp_read_cnt], esi ; Store result
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    mov eax, [tmp_read_cnt] ; Return byte count in EAX
    iret

.sys_getkey:
.sys_getkey_loop:
    call kbd_read_char_blocking
    test al, al
    jz .sys_getkey_loop
    movzx eax, al
    iret

.sys_write:

    pusha
    mov esi, ecx            ; buffer pointer
    mov ecx, edx            ; length
    call vga_print_n
    popa
    iret

.sys_open:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov esi, ebx            ; path
    mov edx, ecx            ; flags

    mov ecx, 3

.sys_open_slot_loop:
    cmp ecx, 16
    jge near .sys_open_full
    mov eax, ecx
    shl eax, 4
    cmp dword [file_table + eax], 0
    je near .sys_open_found_slot
    inc ecx
    jmp near .sys_open_slot_loop

.sys_open_found_slot:
    mov [tmp_fd_slot], ecx

    call fs_lookup_path
    cmp eax, FS_ERR_NOT_FOUND
    je .sys_open_missing
    cmp eax, FS_OK
    jl near .sys_open_fail
    jmp near .sys_open_exists

.sys_open_missing:
    test edx, 2
    jz near .sys_open_fail

    push ebx
    mov esi, ebx
    call fs_create_file_path
    pop ebx
    cmp eax, 0
    jl near .sys_open_fail

    push ebx
    mov esi, ebx
    call fs_lookup_path
    pop ebx
    cmp eax, FS_OK
    jl near .sys_open_fail

.sys_open_exists:
    mov [tmp_open_inode], eax

    test edx, 2
    jz .sys_open_skip_truncate

    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl near .sys_open_fail

    cmp dword [BUF_INODE + INODE_BLOCKS_OFF], 0
    je .sys_open_empty_inode

    mov eax, [BUF_INODE + INODE_START_OFF]
    mov ecx, [BUF_INODE + INODE_BLOCKS_OFF]
    mov [tmp_chain_count], ecx
    mov ebx, ecx
    dec ebx
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl near .sys_open_fail

    mov eax, [BUF_INODE + INODE_START_OFF]
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl near .sys_open_fail
    mov [tmp_chain_next], eax

    mov eax, [BUF_INODE + INODE_START_OFF]
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl near .sys_open_fail

    mov dword [BUF_INODE + INODE_SIZE_OFF], 0
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    mov eax, [tmp_open_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .sys_open_restore_fat

    mov eax, [tmp_chain_next]
    cmp eax, FS_FAT_EOC
    je .sys_open_zero_first
    mov ecx, [tmp_chain_count]
    dec ecx
    call fs_fat_free_chain
    cmp eax, FS_OK
    jl near .sys_open_fail

.sys_open_zero_first:
    mov eax, [BUF_INODE + INODE_START_OFF]
    add eax, FS_DATA_START_LBA
    push edi
    push esi
    mov edi, BUF_SECTOR
    call zero_sector
    pop esi
    pop edi
    push esi
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    pop esi
    jc near .sys_open_fail
    jmp .sys_open_skip_truncate

.sys_open_empty_inode:
    mov dword [BUF_INODE + INODE_SIZE_OFF], 0
    mov eax, [tmp_open_inode]
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl near .sys_open_fail
    jmp .sys_open_skip_truncate

.sys_open_restore_fat:
    mov eax, [BUF_INODE + INODE_START_OFF]
    mov ebx, [tmp_chain_next]
    call fs_fat_write_entry
    jmp near .sys_open_fail

.sys_open_skip_truncate:

    mov ecx, [tmp_fd_slot]
    shl ecx, 4
    mov dword [file_table + ecx], 1
    mov eax, [tmp_open_inode]
    mov dword [file_table + ecx + 4], eax
    mov dword [file_table + ecx + 8], 0
    mov dword [file_table + ecx + 12], edx

    mov eax, [tmp_fd_slot]
    jmp near .sys_open_done

.sys_open_full:
.sys_open_fail:
    mov eax, -1

.sys_open_done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    iret

.sys_close:
    cmp ebx, 3
    jl near .sys_close_err
    cmp ebx, 16
    jge near .sys_close_err

    mov eax, ebx
    shl eax, 4
    mov dword [file_table + eax], 0
    xor eax, eax
    iret

.sys_close_err:
    mov eax, -1
    iret

.sys_read_file:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp ebx, 3
    jl near .sys_rf_err
    cmp ebx, 16
    jge near .sys_rf_err

    mov eax, ebx
    shl eax, 4
    cmp dword [file_table + eax], 1
    jne near .sys_rf_err

    mov [tmp_fd_idx], eax

    mov eax, [file_table + eax + 4]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl near .sys_rf_err

    mov eax, [tmp_fd_idx]
    mov esi, [file_table + eax + 8]
    mov edi, ecx
    mov ecx, edx
    mov edx, [BUF_INODE + INODE_SIZE_OFF]

    cmp esi, edx
    jge near .sys_rf_eof

    mov eax, esi
    add eax, ecx
    cmp eax, edx
    jle near .sys_rf_count_ok
    mov ecx, edx
    sub ecx, esi

.sys_rf_count_ok:
    mov [tmp_rw_count], ecx
    mov dword [tmp_rw_done], 0

.sys_rf_loop:
    cmp dword [tmp_rw_count], 0
    je near .sys_rf_done

    mov ebx, esi
    shr ebx, 9
    mov eax, [BUF_INODE + INODE_START_OFF]
    mov ecx, [BUF_INODE + INODE_BLOCKS_OFF]
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl near .sys_rf_err
    add eax, FS_DATA_START_LBA

    mov ebx, edi
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    mov edi, ebx
    jc near .sys_rf_err

    mov ebx, esi
    and ebx, 511

    mov edx, 512
    sub edx, ebx
    cmp edx, [tmp_rw_count]
    jle near .sys_rf_copy_sz
    mov edx, [tmp_rw_count]

.sys_rf_copy_sz:
    push esi
    push edi
    push ecx

    mov esi, BUF_SECTOR
    add esi, ebx
    mov ecx, edx
    rep movsb

    pop ecx
    pop edi
    pop esi

    add edi, edx
    add esi, edx
    add [tmp_rw_done], edx
    sub [tmp_rw_count], edx
    jmp near .sys_rf_loop

.sys_rf_done:
    mov eax, [tmp_fd_idx]
    mov [file_table + eax + 8], esi
    mov eax, [tmp_rw_done]
    jmp near .sys_rf_exit

.sys_rf_eof:
    xor eax, eax
    jmp near .sys_rf_exit

.sys_rf_err:
    mov eax, -1

.sys_rf_exit:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    iret

.sys_write_file:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp ebx, 3
    jl near .sys_wf_err
    cmp ebx, 16
    jge near .sys_wf_err

    mov eax, ebx
    shl eax, 4
    cmp dword [file_table + eax], 1
    jne near .sys_wf_err

    mov [tmp_fd_idx], eax

    mov eax, [file_table + eax + 4]
    mov [tmp_open_inode], eax
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl near .sys_wf_err

    cmp dword [BUF_INODE + INODE_BLOCKS_OFF], 0
    jne near .sys_wf_has_block

    call fs_fat_alloc_block
    cmp eax, FS_OK
    jl near .sys_wf_err
    mov [BUF_INODE + INODE_START_OFF], eax
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    mov eax, [tmp_open_inode]
    push esi
    mov esi, BUF_INODE
    call fs_write_inode
    pop esi
    cmp eax, FS_OK
    jl .sys_wf_initial_rollback
    jmp .sys_wf_has_block

.sys_wf_initial_rollback:
    mov eax, [BUF_INODE + INODE_START_OFF]
    mov ecx, 1
    call fs_fat_free_chain
    mov dword [BUF_INODE + INODE_START_OFF], 0
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 0
    jmp near .sys_wf_err

.sys_wf_has_block:
    mov eax, [tmp_fd_idx]
    mov esi, [file_table + eax + 8]
    mov edi, ecx
    mov ecx, edx

    mov [tmp_rw_count], ecx
    mov dword [tmp_rw_done], 0

.sys_wf_loop:
    cmp dword [tmp_rw_count], 0
    je near .sys_wf_done

    mov eax, esi
    shr eax, 9
    cmp eax, FS_DATA_BLOCK_COUNT
    jae near .sys_wf_err
    mov [tmp_target_block], eax

.sys_wf_ensure_capacity:
    mov eax, [tmp_target_block]
    cmp eax, [BUF_INODE + INODE_BLOCKS_OFF]
    jb .sys_wf_have_capacity

    mov ecx, [BUF_INODE + INODE_BLOCKS_OFF]
    cmp ecx, 1
    jb near .sys_wf_err
    mov ebx, ecx
    dec ebx
    mov eax, [BUF_INODE + INODE_START_OFF]
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl near .sys_wf_err
    mov [tmp_chain_block], eax

    call fs_fat_alloc_block
    cmp eax, FS_OK
    jl near .sys_wf_err
    mov [tmp_chain_next], eax

    mov ebx, eax
    mov eax, [tmp_chain_block]
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .sys_wf_free_unlinked

    inc dword [BUF_INODE + INODE_BLOCKS_OFF]
    mov eax, [tmp_open_inode]
    push esi
    mov esi, BUF_INODE
    call fs_write_inode
    pop esi
    cmp eax, FS_OK
    jl .sys_wf_rollback_link
    jmp .sys_wf_ensure_capacity

.sys_wf_free_unlinked:
    mov eax, [tmp_chain_block]
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl near .sys_wf_err
    mov eax, [tmp_chain_next]
    mov ecx, 1
    call fs_fat_free_chain
    jmp near .sys_wf_err

.sys_wf_rollback_link:
    dec dword [BUF_INODE + INODE_BLOCKS_OFF]
    mov eax, [tmp_chain_block]
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl near .sys_wf_err
    mov eax, [tmp_chain_next]
    mov ecx, 1
    call fs_fat_free_chain
    jmp near .sys_wf_err

.sys_wf_have_capacity:
    mov eax, [BUF_INODE + INODE_START_OFF]
    mov ebx, [tmp_target_block]
    mov ecx, [BUF_INODE + INODE_BLOCKS_OFF]
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl near .sys_wf_err
    add eax, FS_DATA_START_LBA
    mov [tmp_sector_lba], eax

    mov ebx, edi
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    mov edi, ebx
    jc near .sys_wf_err

    mov ebx, esi
    and ebx, 511

    mov edx, 512
    sub edx, ebx
    cmp edx, [tmp_rw_count]
    jle near .sys_wf_copy_sz
    mov edx, [tmp_rw_count]

.sys_wf_copy_sz:
    push esi
    push edi
    push ecx

    mov esi, edi
    mov edi, BUF_SECTOR
    add edi, ebx
    mov ecx, edx
    rep movsb

    pop ecx
    pop edi
    pop esi

    push eax
    push esi
    mov eax, [tmp_sector_lba]
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    pop esi
    pop eax
    jc near .sys_wf_err

    add edi, edx
    add esi, edx
    add [tmp_rw_done], edx
    sub [tmp_rw_count], edx
    jmp near .sys_wf_loop

.sys_wf_done:
    mov eax, [tmp_fd_idx]
    mov [file_table + eax + 8], esi

    mov eax, [BUF_INODE + INODE_SIZE_OFF]
    cmp esi, eax
    jle .sys_wf_skip_size
    mov [BUF_INODE + INODE_SIZE_OFF], esi
.sys_wf_skip_size:
    mov eax, [tmp_open_inode]
    push esi
    mov esi, BUF_INODE
    call fs_write_inode
    pop esi
    cmp eax, FS_OK
    jl near .sys_wf_err

    mov eax, [tmp_rw_done]
    jmp near .sys_wf_exit

.sys_wf_err:
    mov eax, -1

.sys_wf_exit:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    iret

.sys_lseek:
    push ebx
    push ecx
    push edx
    push esi

    cmp ebx, 3
    jl near .sys_seek_err
    cmp ebx, 16
    jge near .sys_seek_err

    mov eax, ebx
    shl eax, 4
    cmp dword [file_table + eax], 1
    jne near .sys_seek_err

    mov esi, eax

    mov eax, [file_table + esi + 4]
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl near .sys_seek_err
    mov eax, [BUF_INODE + INODE_SIZE_OFF]

    cmp edx, 0
    je near .seek_set
    cmp edx, 1
    je near .seek_cur
    cmp edx, 2
    je near .seek_end
    jmp near .sys_seek_err

.seek_set:
    mov eax, ecx
    jmp near .seek_check

.seek_cur:
    mov eax, [file_table + esi + 8]
    add eax, ecx
    jmp near .seek_check

.seek_end:
    add eax, ecx

.seek_check:
    cmp eax, 0
    jge near .seek_ok
    xor eax, eax

.seek_ok:
    mov [file_table + esi + 8], eax
    jmp near .sys_seek_exit

.sys_seek_err:
    mov eax, -1

.sys_seek_exit:
    pop esi
    pop edx
    pop ecx
    pop ebx
    iret

.sys_move_cursor:
    push ebx
    push ecx
    cmp ebx, 24
    jbe .mc_row_ok
    mov ebx, 24
.mc_row_ok:
    cmp ecx, 79
    jbe .mc_col_ok
    mov ecx, 79
.mc_col_ok:
    mov [cursor_row], ebx
    mov [cursor_col], ecx
    mov byte [cursor_auto_sync], 0
    call vga_sync_cursor
    pop ecx
    pop ebx
    xor eax, eax
    iret

.sys_clear_screen:
    mov byte [cursor_auto_sync], 1
    call vga_clear
    xor eax, eax
    iret

.sys_set_cursor_nosync:
    push ebx
    push ecx
    cmp ebx, 24
    jbe .scns_row_ok
    mov ebx, 24
.scns_row_ok:
    cmp ecx, 79
    jbe .scns_col_ok
    mov ecx, 79
.scns_col_ok:
    mov [cursor_row], ebx
    mov [cursor_col], ecx
    pop ecx
    pop ebx
    xor eax, eax
    iret

.sys_save_screen:
    push esi
    push edi
    push ecx
    mov esi, VGA_BUFFER
    mov edi, saved_vga_buffer
    mov ecx, 4000
    rep movsb
    mov eax, [cursor_row]
    mov [saved_cursor_row], eax
    mov eax, [cursor_col]
    mov [saved_cursor_col], eax
    pop ecx
    pop edi
    pop esi
    xor eax, eax
    iret

.sys_restore_screen:
    push esi
    push edi
    push ecx
    mov esi, saved_vga_buffer
    mov edi, VGA_BUFFER
    mov ecx, 4000
    rep movsb
    mov eax, [saved_cursor_row]
    mov [cursor_row], eax
    mov eax, [saved_cursor_col]
    mov [cursor_col], eax
    mov byte [cursor_auto_sync], 1
    call vga_sync_cursor
    pop ecx
    pop edi
    pop esi
    xor eax, eax
    iret

saved_cursor_row dd 0
saved_cursor_col dd 0
saved_vga_buffer times 4000 db 0

tmp_read_cnt dd 0
current_brk dd 0x00050000
tmp_fd_slot dd 0
tmp_open_inode dd 0
tmp_fd_idx dd 0
tmp_rw_count dd 0
tmp_rw_done dd 0
tmp_sector_lba dd 0
tmp_target_block dd 0
file_table times 256 db 0
