; ----------------------------
; FS bootstrap and formatting
; ----------------------------
fs_bootstrap:
    mov eax, FS_SUPERBLOCK_LBA
    mov edi, BUF_SUPERBLOCK
    call ata_read_sector_lba28

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
    cmp eax, 0
    jne .format_disk

    mov esi, msg_mount_ok
    call vga_print
    ret

.format_disk:
    mov esi, msg_format
    call vga_print
    call fs_format
    ret

; OUT: EAX=0 ok, -1 invalid
fs_validate_root_inode:
    push edi

    mov eax, 0
    mov edi, BUF_INODE
    call fs_read_inode
    cmp byte [BUF_INODE + INODE_TYPE_OFF], 2
    jne .bad
    cmp dword [BUF_INODE + INODE_BLOCKS_OFF], 0
    je .bad
    cmp dword [BUF_INODE + INODE_PARENT_OFF], 0
    jne .bad
    mov eax, [BUF_INODE + INODE_START_OFF]
    cmp eax, FS_DATA_START_LBA
    jl .bad
    mov edx, FS_DATA_START_LBA + FS_DATA_BLOCK_COUNT
    cmp eax, edx
    jge .bad
    xor eax, eax
    pop edi
    ret

.bad:
    mov eax, -1
    pop edi
    ret

fs_set_cwd_root:
    mov dword [cwd_inode], 0
    call fs_rebuild_cwd_path
    ret

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

    mov edi, BUF_SECTOR
    call zero_sector

    mov ecx, 1
    mov ebx, FS_INODE_BMAP_LBA
.clear_inode_bitmap:
    mov eax, ebx
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    inc ebx
    loop .clear_inode_bitmap

    mov ecx, FS_DATA_BMAP_SECS
    mov ebx, FS_DATA_BMAP_LBA
.clear_data_bitmap:
    mov eax, ebx
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    inc ebx
    loop .clear_data_bitmap

    mov ecx, FS_INODE_SECS
    mov ebx, FS_INODE_START_LBA
.clear_inode_array:
    mov eax, ebx
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    inc ebx
    loop .clear_inode_array

    ; Reserve root inode (0), README inode (1), root data block (0), README data block (1).
    mov ebx, 0
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_set
    mov ebx, 1
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_set

    mov ebx, 0
    mov eax, FS_DATA_BMAP_LBA
    call bitmap_set
    mov ebx, 1
    mov eax, FS_DATA_BMAP_LBA
    call bitmap_set

    ; inode 0: root directory
    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov byte [BUF_INODE + INODE_TYPE_OFF], 2
    mov byte [BUF_INODE + INODE_NAME_OFF], '/'
    mov dword [BUF_INODE + INODE_SIZE_OFF], 0
    mov dword [BUF_INODE + INODE_START_OFF], FS_DATA_START_LBA
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    mov dword [BUF_INODE + INODE_PARENT_OFF], 0
    mov eax, 0
    mov esi, BUF_INODE
    call fs_write_inode

    ; inode 1: README.TXT
    mov edi, BUF_INODE
    mov ecx, INODE_SIZE
    call zero_buffer
    mov byte [BUF_INODE + INODE_TYPE_OFF], 1
    mov esi, str_readme_name
    mov edi, BUF_INODE + INODE_NAME_OFF
    call copy_name_27
    mov dword [BUF_INODE + INODE_SIZE_OFF], str_readme_len
    mov dword [BUF_INODE + INODE_START_OFF], FS_DATA_START_LBA + 1
    mov dword [BUF_INODE + INODE_BLOCKS_OFF], 1
    mov dword [BUF_INODE + INODE_PARENT_OFF], 0
    mov eax, 1
    mov esi, BUF_INODE
    call fs_write_inode

    ; root directory entry: README.TXT
    mov edi, BUF_SECTOR
    call zero_sector
    mov dword [BUF_SECTOR + DIR_ENTRY_INODE_OFF], 1
    mov byte [BUF_SECTOR + DIR_ENTRY_TYPE_OFF], 1
    mov esi, str_readme_name
    mov edi, BUF_SECTOR + DIR_ENTRY_NAME_OFF
    call copy_name_27
    mov eax, FS_DATA_START_LBA
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28

    ; README payload
    mov edi, BUF_SECTOR
    call zero_sector
    mov esi, str_readme_content
    mov edi, BUF_SECTOR
    call copy_string
    mov eax, FS_DATA_START_LBA + 1
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28

    mov esi, msg_format_ok
    call vga_print
    call fs_set_cwd_root
    ret
