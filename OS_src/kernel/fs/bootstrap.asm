; ----------------------------
; Filesystem bootstrap and formatting
; ----------------------------

; OUT: EAX=FS_OK or a filesystem error
fs_bootstrap:
    mov eax, FS_SUPERBLOCK_LBA
    mov edi, BUF_SUPERBLOCK
    call ata_read_sector_lba28
    jc .io

    cmp dword [BUF_SUPERBLOCK + 0], FS_MAGIC
    jne .format_disk
    cmp dword [BUF_SUPERBLOCK + 4], FS_INODE_COUNT
    jne .format_disk
    cmp dword [BUF_SUPERBLOCK + 8], FS_DATA_BLOCK_COUNT
    jne .format_disk
    cmp dword [BUF_SUPERBLOCK + 12], FS_INODE_START_LBA
    jne .format_disk
    cmp dword [BUF_SUPERBLOCK + 16], FS_DATA_START_LBA
    jne .format_disk
    cmp dword [BUF_SUPERBLOCK + 20], 0
    jne .format_disk

    call fs_validate_root_inode
    cmp eax, FS_OK
    je .mounted
    cmp eax, FS_ERR_IO
    je .done

.format_disk:
    mov esi, msg_format
    call vga_print
    call fs_format
    ret

.mounted:
    mov esi, msg_mount_ok
    call vga_print
    mov eax, FS_OK
    ret

.io:
    mov eax, FS_ERR_IO
.done:
    ret

; OUT: EAX=FS_OK, FS_ERR_IO, or FS_ERR_CORRUPT
fs_validate_root_inode:
    push ebx
    push edx
    push edi

    mov eax, FS_INODE_BMAP_LBA
    xor ebx, ebx
    call bitmap_test
    cmp eax, FS_OK
    jl .done
    cmp eax, 1
    jne .corrupt

    mov eax, FS_INODE_BMAP_LBA
    mov ebx, 1
    call bitmap_test
    cmp eax, FS_OK
    jl .done
    cmp eax, 1
    jne .corrupt

    xor eax, eax
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    cmp eax, FS_FAT_EOC
    jne .corrupt

    mov eax, 1
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    cmp eax, FS_FAT_EOC
    jne .corrupt

    xor eax, eax
    mov edi, BUF_INODE
    call fs_read_inode
    cmp eax, FS_OK
    jl .done
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .corrupt
    cmp dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    jne .corrupt
    cmp dword [BUF_INODE + INODE_PARENT_OFF], 0
    jne .corrupt

    mov edx, [BUF_INODE + INODE_START_OFF]
    cmp edx, 2
    jb .corrupt
    cmp edx, FS_DATA_BLOCK_COUNT
    jae .corrupt
    mov eax, edx
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    cmp eax, FS_FAT_EOC
    jne .corrupt

    mov eax, FS_OK
    jmp .done

.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop edx
    pop ebx
    ret

; OUT: EAX=FS_OK or a filesystem error
fs_set_cwd_root:
    mov dword [cwd_inode], 0
    call fs_rebuild_cwd_path
    ret

; OUT: EAX=FS_OK or FS_ERR_IO
fs_format:
    mov edi, BUF_SUPERBLOCK
    call zero_sector
    mov dword [BUF_SUPERBLOCK + 0], FS_MAGIC
    mov dword [BUF_SUPERBLOCK + 4], FS_INODE_COUNT
    mov dword [BUF_SUPERBLOCK + 8], FS_DATA_BLOCK_COUNT
    mov dword [BUF_SUPERBLOCK + 12], FS_INODE_START_LBA
    mov dword [BUF_SUPERBLOCK + 16], FS_DATA_START_LBA
    mov dword [BUF_SUPERBLOCK + 20], 0

    mov eax, FS_SUPERBLOCK_LBA
    mov esi, BUF_SUPERBLOCK
    call ata_write_sector_lba28
    jc .io

    mov edi, BUF_SECTOR
    call zero_sector

    mov ecx, 1
    mov ebx, FS_INODE_BMAP_LBA
.clear_inode_bitmap:
    mov eax, ebx
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    jc .io
    inc ebx
    loop .clear_inode_bitmap

    mov ecx, FS_FAT_SECS
    mov ebx, FS_FAT_LBA
.clear_fat:
    mov eax, ebx
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    jc .io
    inc ebx
    loop .clear_fat

    mov ecx, FS_INODE_SECS
    mov ebx, FS_INODE_START_LBA
.clear_inode_array:
    mov eax, ebx
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    jc .io
    inc ebx
    loop .clear_inode_array

    xor ebx, ebx
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_set
    cmp eax, FS_OK
    jl .done
    mov ebx, 1
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_set
    cmp eax, FS_OK
    jl .done

    xor eax, eax
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .done
    mov eax, 1
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .done
    mov eax, 2
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .done
    mov eax, 3
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .done

    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov byte [BUF_INODE + INODE_TYPE_OFF], 2
    mov byte [BUF_INODE + INODE_NAME_OFF], '/'
    mov dword [BUF_INODE + INODE_SIZE_OFF], 0
    mov dword [BUF_INODE + INODE_START_OFF], 2
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    mov dword [BUF_INODE + INODE_PARENT_OFF], 0
    xor eax, eax
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .done

    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov byte [BUF_INODE + INODE_TYPE_OFF], 1
    mov esi, str_readme_name
    mov edi, BUF_INODE + INODE_NAME_OFF
    call copy_name_27
    mov dword [BUF_INODE + INODE_SIZE_OFF], str_readme_len
    mov dword [BUF_INODE + INODE_START_OFF], 3
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    mov dword [BUF_INODE + INODE_PARENT_OFF], 0
    mov eax, 1
    mov esi, BUF_INODE
    call fs_write_inode
    cmp eax, FS_OK
    jl .done

    mov edi, BUF_SECTOR
    call zero_sector
    mov dword [BUF_SECTOR + DIR_ENTRY_INODE_OFF], 1
    mov byte [BUF_SECTOR + DIR_ENTRY_TYPE_OFF], 1
    mov esi, str_readme_name
    mov edi, BUF_SECTOR + DIR_ENTRY_NAME_OFF
    call copy_name_27
    mov eax, FS_DATA_START_LBA + 2
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    jc .io

    mov edi, BUF_SECTOR
    call zero_sector
    mov esi, str_readme_content
    mov edi, BUF_SECTOR
    call copy_string
    mov eax, FS_DATA_START_LBA + 3
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    jc .io

    mov esi, msg_format_ok
    call vga_print
    call fs_set_cwd_root
    ret

.io:
    mov eax, FS_ERR_IO
.done:
    ret
