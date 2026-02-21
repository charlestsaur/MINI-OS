; ----------------------------
; Shell
; ----------------------------
; IN: ESI = command line buffer
shell_dispatch:
    call parse_line

    mov eax, [tok_cmd]
    test eax, eax
    jz .done

    mov esi, [tok_cmd]
    mov edi, cmd_help
    call str_eq_ci
    cmp al, 1
    je .help

    mov esi, [tok_cmd]
    mov edi, cmd_ls
    call str_eq_ci
    cmp al, 1
    je .ls

    mov esi, [tok_cmd]
    mov edi, cmd_pwd
    call str_eq_ci
    cmp al, 1
    je .pwd

    mov esi, [tok_cmd]
    mov edi, cmd_cd
    call str_eq_ci
    cmp al, 1
    je .cd

    mov esi, [tok_cmd]
    mov edi, cmd_mkdir
    call str_eq_ci
    cmp al, 1
    je .mkdir

    mov esi, [tok_cmd]
    mov edi, cmd_touch
    call str_eq_ci
    cmp al, 1
    je .touch

    mov esi, [tok_cmd]
    mov edi, cmd_cat
    call str_eq_ci
    cmp al, 1
    je .cat

    mov esi, [tok_cmd]
    mov edi, cmd_edit
    call str_eq_ci
    cmp al, 1
    je .edit

    mov esi, [tok_cmd]
    mov edi, cmd_rm
    call str_eq_ci
    cmp al, 1
    je .rm

    mov esi, [tok_cmd]
    mov edi, cmd_mv
    call str_eq_ci
    cmp al, 1
    je .mv

    mov esi, [tok_cmd]
    mov edi, cmd_format
    call str_eq_ci
    cmp al, 1
    je .format

    mov esi, msg_unknown
    call vga_print
    jmp .done

.help:
    mov esi, msg_help
    call vga_print
    jmp .done

.ls:
    call fs_list_cwd
    jmp .done

.pwd:
    mov esi, cwd_path
    call vga_print
    call vga_newline
    jmp .done

.cd:
    mov esi, [tok_arg1]
    test esi, esi
    jz .cd_usage
    call fs_change_dir_path
    cmp eax, 0
    je .done
    cmp eax, -2
    je .not_dir
    mov esi, msg_not_found
    call vga_print
    jmp .done
.cd_usage:
    mov esi, msg_usage_cd
    call vga_print
    jmp .done

.mkdir:
    mov esi, [tok_arg1]
    test esi, esi
    jz .mkdir_usage
    call fs_create_dir_path
    cmp eax, 0
    je .mkdir_ok
    cmp eax, -1
    je .exists
    cmp eax, -2
    je .no_inode
    cmp eax, -3
    je .no_data
    cmp eax, -4
    je .invalid_path
    mov esi, msg_not_dir
    call vga_print
    jmp .done
.mkdir_ok:
    mov esi, msg_mkdir_ok
    call vga_print
    mov esi, [tok_arg1]
    call vga_print
    call vga_newline
    jmp .done
.mkdir_usage:
    mov esi, msg_usage_mkdir
    call vga_print
    jmp .done

.touch:
    mov esi, [tok_arg1]
    test esi, esi
    jz .touch_usage
    call fs_create_file_path
    cmp eax, 0
    je .touch_ok
    cmp eax, -1
    je .exists
    cmp eax, -2
    je .no_inode
    cmp eax, -4
    je .invalid_path
    mov esi, msg_not_dir
    call vga_print
    jmp .done
.touch_ok:
    mov esi, msg_touch_ok
    call vga_print
    mov esi, [tok_arg1]
    call vga_print
    call vga_newline
    jmp .done
.touch_usage:
    mov esi, msg_usage_touch
    call vga_print
    jmp .done

.cat:
    mov esi, [tok_arg1]
    test esi, esi
    jz .cat_usage
    call shell_cat
    jmp .done
.cat_usage:
    mov esi, msg_usage_cat
    call vga_print
    jmp .done

.edit:
    mov esi, [tok_arg1]
    test esi, esi
    jz .edit_usage
    call shell_edit
    jmp .done
.edit_usage:
    mov esi, msg_usage_edit
    call vga_print
    jmp .done

.rm:
    mov esi, [tok_arg1]
    test esi, esi
    jz .rm_usage
    call fs_remove_path
    cmp eax, 0
    je .rm_ok
    cmp eax, -2
    je .not_empty
    cmp eax, -3
    je .rm_deny
    mov esi, msg_not_found
    call vga_print
    jmp .done
.rm_ok:
    mov esi, msg_rm_ok
    call vga_print
    jmp .done
.rm_usage:
    mov esi, msg_usage_rm
    call vga_print
    jmp .done

.mv:
    mov esi, [tok_arg1]
    test esi, esi
    jz .mv_usage
    mov edi, [tok_arg2]
    test edi, edi
    jz .mv_usage
    call fs_rename_path
    cmp eax, 0
    je .mv_ok
    cmp eax, -2
    je .exists
    cmp eax, -3
    je .mv_invalid
    mov esi, msg_not_found
    call vga_print
    jmp .done
.mv_ok:
    mov esi, msg_mv_ok
    call vga_print
    jmp .done
.mv_usage:
    mov esi, msg_usage_mv
    call vga_print
    jmp .done

.format:
    call fs_format
    call fs_set_cwd_root
    jmp .done

.exists:
    mov esi, msg_exists
    call vga_print
    jmp .done

.no_inode:
    mov esi, msg_no_inode
    call vga_print
    jmp .done

.no_data:
    mov esi, msg_no_data
    call vga_print
    jmp .done

.not_file:
    mov esi, msg_not_file
    call vga_print
    jmp .done

.not_empty:
    mov esi, msg_not_empty
    call vga_print
    jmp .done

.not_dir:
    mov esi, msg_not_dir
    call vga_print
    jmp .done

.rm_deny:
    mov esi, msg_rm_deny
    call vga_print
    jmp .done

.invalid_path:
    mov esi, msg_invalid_path
    call vga_print
    jmp .done

.mv_invalid:
    mov esi, msg_mv_invalid
    call vga_print
    jmp .done

.done:
    ret

; IN: ESI = line buffer, modifies it by replacing spaces with 0
parse_line:
    mov dword [tok_cmd], 0
    mov dword [tok_arg1], 0
    mov dword [tok_arg2], 0

    call skip_spaces
    cmp byte [esi], 0
    je .done
    mov [tok_cmd], esi
    call cut_token

    call skip_spaces
    cmp byte [esi], 0
    je .done
    mov [tok_arg1], esi
    call cut_token

    call skip_spaces
    cmp byte [esi], 0
    je .done
    mov [tok_arg2], esi
    call cut_token

.done:
    ret

; IN/OUT: ESI
skip_spaces:
.loop:
    cmp byte [esi], ' '
    jne .done
    inc esi
    jmp .loop
.done:
    ret

; IN/OUT: ESI. If token ended by space, writes 0 and advances.
cut_token:
.loop:
    mov al, [esi]
    cmp al, 0
    je .done
    cmp al, ' '
    je .split
    inc esi
    jmp .loop
.split:
    mov byte [esi], 0
    inc esi
.done:
    ret

; ----------------------------
; File handlers
; ----------------------------
; IN: ESI=file name
shell_cat:
    push esi
    call fs_lookup_path
    cmp eax, -1
    je .not_found

    mov edi, BUF_INODE
    call fs_read_inode
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 1
    jne .not_file

    mov ecx, [BUF_INODE + INODE_SIZE_OFF]
    cmp ecx, 0
    je .empty

    cmp dword [BUF_INODE + INODE_BLOCKS_OFF], 0
    je .empty

    mov eax, [BUF_INODE + INODE_START_OFF]
    cmp eax, FS_DATA_START_LBA
    jl .not_file
    mov edx, FS_DATA_START_LBA + FS_DATA_BLOCK_COUNT
    cmp eax, edx
    jge .not_file
    mov edi, BUF_TEXT
    call ata_read_sector_lba28

    mov esi, BUF_TEXT
    call vga_print_n
    call vga_newline
    pop esi
    ret

.empty:
    mov esi, msg_empty
    call vga_print
    pop esi
    ret

.not_file:
    mov esi, msg_not_file
    call vga_print
    pop esi
    ret

.not_found:
    mov esi, msg_not_found
    call vga_print
    pop esi
    ret

; IN: ESI=file name
shell_edit:
    push esi
    call fs_lookup_path
    cmp eax, -1
    jne .have_inode

    pop esi
    push esi
    call fs_create_file_path
    cmp eax, 0
    jne .create_fail

    pop esi
    push esi
    call fs_lookup_path
    cmp eax, -1
    je .create_fail

.have_inode:
    mov [tmp_inode_idx], eax
    mov edi, BUF_INODE
    call fs_read_inode
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 1
    jne .not_file

    mov esi, msg_edit_prompt
    call vga_print

    mov edi, BUF_TEXT
    mov ecx, 510
    call kbd_read_text
    mov [tmp_data_lba], eax

    cmp dword [BUF_INODE + INODE_BLOCKS_OFF], 0
    jne .have_block

    call fs_alloc_data_block
    cmp eax, -1
    je .no_data
    mov [BUF_INODE + INODE_START_OFF], eax
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1

.have_block:
    mov eax, [BUF_INODE + INODE_START_OFF]
    cmp eax, FS_DATA_START_LBA
    jl .bad_block
    mov edx, FS_DATA_START_LBA + FS_DATA_BLOCK_COUNT
    cmp eax, edx
    jge .bad_block

    mov edi, BUF_SECTOR
    call zero_sector

    mov esi, BUF_TEXT
    mov edi, BUF_SECTOR
    mov ecx, [tmp_data_lba]
    inc ecx
    call copy_bytes

    mov eax, [BUF_INODE + INODE_START_OFF]
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28

    mov eax, [tmp_data_lba]
    mov [BUF_INODE + INODE_SIZE_OFF], eax

    mov eax, [tmp_inode_idx]
    mov esi, BUF_INODE
    call fs_write_inode

    mov esi, msg_edit_ok
    call vga_print
    pop esi
    ret

.create_fail:
    mov esi, msg_no_inode
    call vga_print
    pop esi
    ret

.not_file:
    mov esi, msg_not_file
    call vga_print
    pop esi
    ret

.no_data:
    mov esi, msg_no_data
    call vga_print
    pop esi
    ret

.bad_block:
    mov esi, msg_not_file
    call vga_print
    pop esi
    ret
