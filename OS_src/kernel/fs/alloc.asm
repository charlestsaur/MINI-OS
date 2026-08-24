; ----------------------------
; Inode, FAT, and bitmap helpers
; ----------------------------

; OUT: EAX=inode index, or a filesystem error
fs_alloc_inode:
    push ebx
    push ecx

    mov ecx, 1
.loop:
    cmp ecx, FS_INODE_COUNT
    jge .full
    mov ebx, ecx
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_test
    cmp eax, FS_OK
    jl .done
    cmp eax, 0
    je .alloc
    inc ecx
    jmp .loop

.alloc:
    mov ebx, ecx
    mov eax, FS_INODE_BMAP_LBA
    call bitmap_set
    cmp eax, FS_OK
    jl .done
    mov eax, ecx
    jmp .done

.full:
    mov eax, FS_ERR_NO_INODE
.done:
    pop ecx
    pop ebx
    ret

; IN: EAX=block index
; OUT: EAX=16-bit FAT entry, or a filesystem error
fs_fat_read_entry:
    push ebx
    push ecx
    push edx
    push edi

    cmp eax, FS_DATA_BLOCK_COUNT
    jae .invalid

    mov ecx, eax
    shr ecx, 8
    mov edx, eax
    and edx, 0xFF
    shl edx, 1

    mov eax, FS_FAT_LBA
    add eax, ecx
    mov edi, BUF_BITMAP
    call ata_read_sector_lba28
    jc .io

    movzx eax, word [BUF_BITMAP + edx]
    jmp .done

.invalid:
    mov eax, FS_ERR_CORRUPT
    jmp .done
.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=block index, EBX=FAT value
; OUT: EAX=FS_OK or a filesystem error
fs_fat_write_entry:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp eax, FS_DATA_BLOCK_COUNT
    jae .invalid
    cmp ebx, 0
    je .value_ok
    cmp ebx, FS_FAT_EOC
    je .value_ok
    cmp ebx, 2
    jb .invalid
    cmp ebx, FS_DATA_BLOCK_COUNT
    jae .invalid

.value_ok:
    mov ecx, eax
    shr ecx, 8
    mov edx, eax
    and edx, 0xFF
    shl edx, 1

    mov eax, FS_FAT_LBA
    add eax, ecx
    mov edi, BUF_BITMAP
    call ata_read_sector_lba28
    jc .io

    mov word [BUF_BITMAP + edx], bx
    mov esi, BUF_BITMAP
    call ata_write_sector_lba28
    jc .io

    mov eax, FS_OK
    jmp .done

.invalid:
    mov eax, FS_ERR_CORRUPT
    jmp .done
.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; Clear the in-memory FAT traversal bitmap.
fs_chain_reset:
    push edi
    mov edi, FS_VISITED_BUF
    call zero_sector
    pop edi
    ret

; IN: EAX=block index
; OUT: EAX=FS_OK, or FS_ERR_CORRUPT if invalid/already visited
fs_chain_visit_block:
    push ebx
    push ecx
    push edx

    cmp eax, 2
    jb .corrupt
    cmp eax, FS_DATA_BLOCK_COUNT
    jae .corrupt

    mov ebx, eax
    mov ecx, eax
    shr ebx, 3
    and ecx, 7
    mov dl, 1
    shl dl, cl
    test [FS_VISITED_BUF + ebx], dl
    jnz .corrupt
    or [FS_VISITED_BUF + ebx], dl
    mov eax, FS_OK
    jmp .done

.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=start block, EBX=zero-based block index, ECX=declared block count
; OUT: EAX=block index or a filesystem error
fs_fat_get_nth_block:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp ecx, 1
    jb .corrupt
    cmp ecx, FS_DATA_BLOCK_COUNT
    ja .corrupt
    cmp ebx, ecx
    jae .corrupt

    mov edx, eax
    mov esi, ebx
    mov edi, ecx
    call fs_chain_reset

.walk:
    mov eax, edx
    call fs_chain_visit_block
    cmp eax, FS_OK
    jl .done
    cmp esi, 0
    je .target

    mov eax, edx
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    cmp eax, FS_FAT_EOC
    je .corrupt
    mov edx, eax
    dec esi
    jmp .walk

.target:
    mov eax, ebx
    inc eax
    cmp eax, edi
    jne .success
    mov eax, edx
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    cmp eax, FS_FAT_EOC
    jne .corrupt

.success:
    mov eax, edx
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

; OUT: EAX=allocated block index, or a filesystem error
fs_fat_alloc_block:
    push ebx
    push ecx
    push esi
    push edi

    mov ecx, 2
.scan:
    cmp ecx, FS_DATA_BLOCK_COUNT
    jge .full
    mov eax, ecx
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    cmp eax, 0
    je .claim
    inc ecx
    jmp .scan

.claim:
    mov [tmp_alloc_block], ecx
    mov eax, ecx
    mov ebx, FS_FAT_EOC
    call fs_fat_write_entry
    cmp eax, FS_OK
    jl .done

    mov edi, BUF_SECTOR
    call zero_sector
    mov eax, [tmp_alloc_block]
    add eax, FS_DATA_START_LBA
    mov esi, BUF_SECTOR
    call ata_write_sector_lba28
    jc .rollback

    mov eax, [tmp_alloc_block]
    jmp .done

.rollback:
    mov eax, [tmp_alloc_block]
    xor ebx, ebx
    call fs_fat_write_entry
    mov eax, FS_ERR_IO
    jmp .done

.full:
    mov eax, FS_ERR_NO_DATA
.done:
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

; IN: EAX=starting block index, or zero for no chain
;     ECX=declared block count
; OUT: EAX=FS_OK or a filesystem error
fs_fat_free_chain:
    push ebx
    push ecx
    push edx
    push esi

    test ecx, ecx
    jz .expect_no_chain
    cmp ecx, FS_DATA_BLOCK_COUNT
    ja .corrupt
    cmp eax, 2
    jb .corrupt
    cmp eax, FS_DATA_BLOCK_COUNT
    jae .corrupt

    ; Validate the complete declared chain before making any block reusable.
    mov esi, eax
    mov edx, ecx
    mov ebx, ecx
    dec ebx
    call fs_fat_get_nth_block
    cmp eax, FS_OK
    jl .done
    mov eax, esi
    mov ecx, edx

.loop:
    mov esi, eax
    call fs_fat_read_entry
    cmp eax, FS_OK
    jl .done
    mov ebx, eax
    mov eax, esi
    push ebx
    xor ebx, ebx
    call fs_fat_write_entry
    pop ebx
    cmp eax, FS_OK
    jl .done
    dec ecx
    jz .success
    mov eax, ebx
    jmp .loop

.expect_no_chain:
    test eax, eax
    jnz .corrupt
.success:
    mov eax, FS_OK
    jmp .done
.corrupt:
    mov eax, FS_ERR_CORRUPT
.done:
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=inode index, EDI=destination (64 bytes)
; OUT: EAX=FS_OK or a filesystem error
fs_read_inode:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp eax, FS_INODE_COUNT
    jae .invalid
    mov ebx, eax
    mov edx, edi

    shr eax, 3
    add eax, FS_INODE_START_LBA
    mov ecx, ebx
    and ecx, 7
    shl ecx, 6

    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    jc .io

    mov esi, BUF_SECTOR
    add esi, ecx
    mov edi, edx
    mov ecx, INODE_SIZE
    call copy_bytes
    mov eax, FS_OK
    jmp .done

.invalid:
    mov ecx, INODE_SIZE
    call zero_buffer
    mov eax, FS_ERR_CORRUPT
    jmp .done
.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=inode index, ESI=source (64 bytes)
; OUT: EAX=FS_OK or a filesystem error
fs_write_inode:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp eax, FS_INODE_COUNT
    jae .invalid
    mov ebx, eax
    mov edx, esi

    shr eax, 3
    add eax, FS_INODE_START_LBA
    mov ecx, ebx
    and ecx, 7
    shl ecx, 6

    mov edi, BUF_SECTOR
    call ata_read_sector_lba28
    jc .io

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
    jc .io
    mov eax, FS_OK
    jmp .done

.invalid:
    mov eax, FS_ERR_CORRUPT
    jmp .done
.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=bitmap base LBA, EBX=bit index
; OUT: EAX=0/1 or a filesystem error
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
    jc .io

    movzx eax, byte [BUF_BITMAP + ecx]
    mov cl, bl
    and cl, 7
    shr eax, cl
    and eax, 1
    jmp .done

.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=bitmap base LBA, EBX=bit index
; OUT: EAX=FS_OK or a filesystem error
bitmap_set:
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
    jc .io

    mov esi, ecx
    mov dl, 1
    mov cl, bl
    and cl, 7
    shl dl, cl
    or [BUF_BITMAP + esi], dl

    mov esi, BUF_BITMAP
    call ata_write_sector_lba28
    jc .io
    mov eax, FS_OK
    jmp .done

.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; IN: EAX=bitmap base LBA, EBX=bit index
; OUT: EAX=FS_OK or a filesystem error
bitmap_clear:
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
    jc .io

    mov esi, ecx
    mov dl, 1
    mov cl, bl
    and cl, 7
    shl dl, cl
    not dl
    and [BUF_BITMAP + esi], dl

    mov esi, BUF_BITMAP
    call ata_write_sector_lba28
    jc .io
    mov eax, FS_OK
    jmp .done

.io:
    mov eax, FS_ERR_IO
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
