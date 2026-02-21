; ----------------------------
; Generic inode / bitmap helpers
; ----------------------------
; OUT: EAX = inode index, -1 if full
fs_alloc_inode:
    push ebx
    push ecx

    mov ecx, 2
.loop:
    cmp ecx, FS_INODE_COUNT
    jge .full
    mov ebx, ecx
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_test
    cmp al, 0
    je .alloc
    inc ecx
    jmp .loop

.alloc:
    mov ebx, ecx
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_set
    mov eax, ecx
    pop ecx
    pop ebx
    ret

.full:
    mov eax, -1
    pop ecx
    pop ebx
    ret

; IN: EBX=data block index (relative to FS_DATA_START_LBA)
; OUT: EAX=0 success, -1 fail
fs_alloc_data_block_index:
    cmp ebx, 0
    jl .fail
    cmp ebx, FS_DATA_BLOCK_COUNT
    jge .fail

    mov eax, FS_DATA_BMAP_LBA
    call bitmap_test
    cmp al, 1
    je .fail

    mov eax, FS_DATA_BMAP_LBA
    call bitmap_set
    xor eax, eax
    ret

.fail:
    mov eax, -1
    ret

; OUT: EAX = data LBA, -1 if full
fs_alloc_data_block:
    push ebx
    push ecx

    mov ecx, 2
.loop:
    cmp ecx, FS_DATA_BLOCK_COUNT
    jge .full
    mov ebx, ecx
    mov eax, FS_DATA_BMAP_LBA
    call bitmap_test
    cmp al, 0
    je .alloc
    inc ecx
    jmp .loop

.alloc:
    mov ebx, ecx
    mov eax, FS_DATA_BMAP_LBA
    call bitmap_set
    mov eax, FS_DATA_START_LBA
    add eax, ecx
    pop ecx
    pop ebx
    ret

.full:
    mov eax, -1
    pop ecx
    pop ebx
    ret

; IN: EAX = data block LBA
fs_free_data_block_lba:
    push ebx
    cmp eax, FS_DATA_START_LBA
    jl .done
    sub eax, FS_DATA_START_LBA
    cmp eax, FS_DATA_BLOCK_COUNT
    jge .done
    mov ebx, eax
    mov eax, FS_DATA_BMAP_LBA
    call bitmap_clear
.done:
    pop ebx
    ret

; IN: EAX = inode index, EDI = dest (64 bytes)
fs_read_inode:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp eax, FS_INODE_COUNT
    jb .read_inode
    mov ecx, INODE_SIZE
    call zero_buffer
    jmp .done

.read_inode:
    mov ebx, eax
    mov edx, edi

    mov eax, ebx
    shr eax, 3
    add eax, FS_INODE_START_LBA

    mov ecx, ebx
    and ecx, 7
    shl ecx, 6

    mov edi, BUF_SECTOR
    call ata_read_sector_lba28

    mov esi, BUF_SECTOR
    add esi, ecx
    mov edi, edx
    mov ecx, INODE_SIZE
    call copy_bytes

.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX = inode index, ESI = src (64 bytes)
fs_write_inode:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp eax, FS_INODE_COUNT
    jae .done

    mov ebx, eax
    mov edx, esi

    mov eax, ebx
    shr eax, 3
    add eax, FS_INODE_START_LBA

    mov ecx, ebx
    and ecx, 7
    shl ecx, 6

    mov edi, BUF_SECTOR
    call ata_read_sector_lba28

    mov esi, edx
    mov edi, BUF_SECTOR
    add edi, ecx
    mov ecx, INODE_SIZE
    call copy_bytes

    mov eax, ebx
    shr eax, 3
    add eax, FS_INODE_START_LBA
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28

.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX = bitmap base LBA, EBX = bit index
; OUT: AL = 0/1
bitmap_test:
    push ebx
    push ecx
    push edx
    push edi

    mov ecx, ebx
    shr ecx, 3
    mov edx, ecx
    shr edx, 9
    and ecx, 0x1FF

    add eax, edx
    mov edi, BUF_BITMAP
    call ata_read_sector_lba28

    mov al, [BUF_BITMAP + ecx]
    mov cl, bl
    and cl, 7
    shr al, cl
    and al, 1

    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX = bitmap base LBA, EBX = bit index
bitmap_set:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov ecx, ebx
    shr ecx, 3
    mov edx, ecx
    shr edx, 9
    and ecx, 0x1FF

    add eax, edx
    mov edi, BUF_BITMAP
    call ata_read_sector_lba28

    mov esi, ecx
    mov dl, 1
    mov cl, bl
    and cl, 7
    shl dl, cl
    or [BUF_BITMAP + esi], dl

    mov esi, BUF_BITMAP
    call ata_write_sector_lba28

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; IN: EAX = bitmap base LBA, EBX = bit index
bitmap_clear:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov ecx, ebx
    shr ecx, 3
    mov edx, ecx
    shr edx, 9
    and ecx, 0x1FF

    add eax, edx
    mov edi, BUF_BITMAP
    call ata_read_sector_lba28

    mov esi, ecx
    mov dl, 1
    mov cl, bl
    and cl, 7
    shl dl, cl
    not dl
    and [BUF_BITMAP + esi], dl

    mov esi, BUF_BITMAP
    call ata_write_sector_lba28

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret
