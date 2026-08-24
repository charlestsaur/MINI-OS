; ----------------------------
; Filesystem bootstrap and formatting
; ----------------------------

KERNEL_CODE_DISK_LBA equ 1 + ((kernel_start - $$) / 512)
KERNEL_CODE_SECTOR_OFF equ (kernel_start - $$) & 511
%if KERNEL_CODE_SECTOR_OFF + KERNEL_CODE_CHECK_LEN > 512
    %error "kernel device-identity sample crosses a sector boundary"
%endif

; Verify that protected-mode ATA I/O reaches the device that supplied the
; running boot and kernel code.  Images sharing all checked identity/code bytes
; cannot be distinguished, but an unrelated primary master is never mounted or
; formatted merely because it occupies the expected ATA slot.
; OUT: EAX=FS_OK, FS_ERR_IO, or FS_ERR_WRONG_DEVICE
fs_verify_boot_device:
    push ecx
    push esi
    push edi

    xor eax, eax
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    jc .io
    mov esi, BOOT_CODE_ADDR
    mov edi, BUF_SECTOR
    mov ecx, BOOT_CODE_CHECK_LEN
    repe cmpsb
    jne .wrong

    mov esi, BOOT_VOLUME_ID_ADDR
    mov edi, BUF_SECTOR + FS_BOOT_ID_OFFSET
    mov ecx, FS_BOOT_ID_SIZE
    xor edx, edx
.check_volume_id:
    mov al, [esi]
    or dl, al
    cmp al, [edi]
    jne .wrong
    inc esi
    inc edi
    loop .check_volume_id
    test dl, dl
    jz .wrong

    mov eax, KERNEL_CODE_DISK_LBA
    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    jc .io
    mov esi, kernel_start
    mov edi, BUF_SECTOR + KERNEL_CODE_SECTOR_OFF
    mov ecx, KERNEL_CODE_CHECK_LEN
    repe cmpsb
    jne .wrong

    mov eax, FS_OK
    jmp .done
.wrong:
    mov eax, FS_ERR_WRONG_DEVICE
    jmp .done
.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop esi
    pop ecx
    ret

; OUT: EAX=FS_OK when the immutable superblock fields match this kernel.
fs_validate_superblock_layout:
    cmp dword [BUF_SUPERBLOCK + 0], FS_MAGIC
    jne .corrupt
    cmp dword [BUF_SUPERBLOCK + 4], FS_INODE_COUNT
    jne .corrupt
    cmp dword [BUF_SUPERBLOCK + 8], FS_DATA_BLOCK_COUNT
    jne .corrupt
    cmp dword [BUF_SUPERBLOCK + 12], FS_INODE_START_LBA
    jne .corrupt
    cmp dword [BUF_SUPERBLOCK + 16], FS_DATA_START_LBA
    jne .corrupt
    cmp dword [BUF_SUPERBLOCK + 20], 0
    jne .corrupt
    mov eax, FS_OK
    ret
.corrupt:
    mov eax, FS_ERR_CORRUPT
    ret

; Begin a persistent filesystem mutation.  A dirty superblock is never mounted,
; so a reset or I/O error cannot silently turn a partial operation into the next
; session's starting state.
; OUT: EAX=FS_OK or a filesystem error
fs_begin_mutation:
    cmp byte [fs_io_poisoned], 0
    jne .io
    cmp byte [fs_mutation_active], 0
    jne .corrupt

    mov eax, FS_SUPERBLOCK_LBA
    mov edi, BUF_SUPERBLOCK
    call ata_read_sector_lba28
    jc .read_error
    call fs_validate_superblock_layout
    cmp eax, FS_OK
    jne .corrupt
    cmp dword [BUF_SUPERBLOCK + FS_SUPER_DIRTY_OFFSET], 0
    jne .corrupt
    mov dword [BUF_SUPERBLOCK + FS_SUPER_DIRTY_OFFSET], 1
    mov eax, FS_SUPERBLOCK_LBA
    mov esi, BUF_SUPERBLOCK
    call ata_write_sector_lba28
    jc .io
    mov byte [fs_mutation_active], 1
    mov byte [fs_mutation_touched], 0
    mov eax, FS_OK
    ret

.read_error:
    mov byte [fs_io_poisoned], 1
.io:
    mov eax, FS_ERR_IO
    ret
.corrupt:
    mov eax, FS_ERR_CORRUPT
    ret

; IN: EAX=operation result
; OUT: the preserved result after a clean marker, or FS_ERR_IO.  An I/O failure,
; or any later error after a successful operation write, leaves the dirty marker
; in place and poisons writes for the rest of the boot.
fs_complete_mutation:
    mov [tmp_mutation_result], eax
    cmp byte [fs_mutation_active], 1
    jne .return_saved
    cmp eax, FS_ERR_IO
    je .poison
    cmp byte [fs_io_poisoned], 0
    jne .io
    cmp eax, FS_OK
    jge .clear_marker
    cmp byte [fs_mutation_touched], 0
    jne .poison

.clear_marker:
    mov eax, FS_SUPERBLOCK_LBA
    mov edi, BUF_SUPERBLOCK
    call ata_read_sector_lba28
    jc .poison
    call fs_validate_superblock_layout
    cmp eax, FS_OK
    jne .poison
    cmp dword [BUF_SUPERBLOCK + FS_SUPER_DIRTY_OFFSET], 1
    jne .poison
    mov dword [BUF_SUPERBLOCK + FS_SUPER_DIRTY_OFFSET], 0
    mov eax, FS_SUPERBLOCK_LBA
    mov esi, BUF_SUPERBLOCK
    call ata_write_sector_lba28
    jc .io
    mov byte [fs_mutation_active], 0
    mov byte [fs_mutation_touched], 0
.return_saved:
    mov eax, [tmp_mutation_result]
    ret

.poison:
    mov byte [fs_io_poisoned], 1
.io:
    mov eax, FS_ERR_IO
    ret

; OUT: EAX=FS_OK or a filesystem error
fs_bootstrap:
    call fs_verify_boot_device
    cmp eax, FS_OK
    jne .done

    mov eax, FS_SUPERBLOCK_LBA
    mov edi, BUF_SUPERBLOCK
    call ata_read_sector_lba28
    jc .io

    call fs_validate_superblock_layout
    cmp eax, FS_OK
    jne .corrupt
    cmp dword [BUF_SUPERBLOCK + FS_SUPER_DIRTY_OFFSET], 0
    jne .corrupt

    call fs_validate_root_inode
    cmp eax, FS_OK
    je .mounted
    cmp eax, FS_ERR_IO
    je .done
    jmp .corrupt

.mounted:
    mov esi, msg_mount_ok
    call vga_print
    mov eax, FS_OK
    ret

.io:
    mov eax, FS_ERR_IO
    ret
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    ret

; OUT: EAX=FS_OK, FS_ERR_IO, or FS_ERR_CORRUPT
fs_validate_root_inode:
    push ebx
    push ecx
    push edx
    push edi

    mov eax, FS_INODE_BMAP_LBA
    xor ebx, ebx
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
    cmp byte [BUF_INODE + INODE_NAME_OFF], '/'
    jne .corrupt
    cmp byte [BUF_INODE + INODE_NAME_OFF + 1], 0
    jne .corrupt
    cmp dword [BUF_INODE + INODE_SIZE_OFF], 0
    jne .corrupt
    cmp dword [BUF_INODE + INODE_PARENT_OFF], 0
    jne .corrupt

    mov ecx, [BUF_INODE + INODE_BLOCKS_OFF]
    cmp ecx, 1
    jb .corrupt
    cmp ecx, FS_DATA_BLOCK_COUNT
    ja .corrupt
    mov eax, [BUF_INODE + INODE_START_OFF]
    mov ebx, ecx
    dec ebx
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl .done

    mov eax, FS_OK
    jmp .done

.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; OUT: EAX=FS_OK or a filesystem error
fs_set_cwd_root:
    mov dword [cwd_inode], 0
    call fs_rebuild_cwd_path
    ret

; OUT: EAX=FS_OK or FS_ERR_IO
fs_format:
    call fs_begin_mutation
    cmp eax, FS_OK
    jl .return

    mov edi, BUF_SUPERBLOCK
    call zero_sector
    mov dword [BUF_SUPERBLOCK + 0], FS_MAGIC
    mov dword [BUF_SUPERBLOCK + 4], FS_INODE_COUNT
    mov dword [BUF_SUPERBLOCK + 8], FS_DATA_BLOCK_COUNT
    mov dword [BUF_SUPERBLOCK + 12], FS_INODE_START_LBA
    mov dword [BUF_SUPERBLOCK + 16], FS_DATA_START_LBA
    mov dword [BUF_SUPERBLOCK + 20], 0
    mov dword [BUF_SUPERBLOCK + FS_SUPER_DIRTY_OFFSET], 0

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
    jl .fail
    mov ebx, 1
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_set
    cmp eax, FS_OK
    jl .fail

    xor eax, eax
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .fail
    mov eax, 1
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .fail
    mov eax, 2
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .fail
    mov eax, 3
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .fail

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
    jl .fail

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
    jl .fail

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

    ; Commit the new format last.  Until this write succeeds, mount sees the
    ; dirty marker installed by fs_begin_mutation and refuses the disk.
    mov eax, FS_SUPERBLOCK_LBA
    mov esi, BUF_SUPERBLOCK
    call ata_write_sector_lba28
    jc .io
    mov byte [fs_mutation_active], 0
    mov byte [fs_mutation_touched], 0

    mov esi, msg_format_ok
    call vga_print
    call fs_set_cwd_root
    ret

.io:
    mov eax, FS_ERR_IO
.fail:
    mov byte [fs_io_poisoned], 1
.return:
    ret
