[bits 16]
[org 0x7c00]

; Kernel load target physical address starts at 0x8000.
; We keep offset=0 and grow segment by 0x20 per sector (512 bytes),
; so the transfer buffer never crosses a 64 KiB boundary in one request.
KERNEL_LOAD_SEG equ 0x0800
KERNEL_ENTRY    equ 0x8000

%ifndef KERNEL_SECTORS
KERNEL_SECTORS  equ 32
%endif

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    sti

    mov [boot_drive], dl

    call load_kernel
    jc boot_fail

    cli
    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 0x1
    mov cr0, eax
    jmp 0x08:init_pm

boot_fail:
    mov al, 'F'
    call putc
    jmp $

; ----------------------------
; Disk loading strategy
; ----------------------------
; 1) Try INT13h extensions (AH=41h + AH=42h).
; 2) Fallback to CHS one-sector reads (AH=02h) if EDD is unavailable.
; OUT: CF clear on success, set on failure.
load_kernel:
    call detect_edd
    jc .chs

    mov al, 'E'
    call putc
    call load_kernel_edd
    jnc .ok

.chs:
    mov al, 'C'
    call putc
    call load_kernel_chs
    jc .fail

.ok:
    clc
    ret

.fail:
    stc
    ret

; OUT: CF clear if EDD is supported
detect_edd:
    mov ah, 0x41
    mov bx, 0x55aa
    mov dl, [boot_drive]
    int 0x13
    jc .no
    cmp bx, 0xaa55
    jne .no
    test cx, 1
    jz .no
    clc
    ret
.no:
    stc
    ret

; ----------------------------
; EDD path (AH=42h), one sector per request with retries
; OUT: CF clear on success
load_kernel_edd:
    mov word [load_seg], KERNEL_LOAD_SEG
    mov dword [load_lba_low], 1
    mov dword [load_lba_high], 0
    mov cx, KERNEL_SECTORS

.next_sector:
    cmp cx, 0
    je .ok

    mov byte [retry_count], 3
.retry:
    mov ax, [load_seg]
    mov [disk_packet + 6], ax
    mov eax, [load_lba_low]
    mov [disk_packet + 8], eax
    mov eax, [load_lba_high]
    mov [disk_packet + 12], eax

    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, disk_packet
    int 0x13
    jnc .read_ok

    call disk_reset
    dec byte [retry_count]
    jnz .retry
    stc
    ret

.read_ok:
    add word [load_seg], 0x20
    inc dword [load_lba_low]
    jnz .cont
    inc dword [load_lba_high]
.cont:
    dec cx
    jmp .next_sector

.ok:
    clc
    ret

disk_reset:
    mov ah, 0x00
    mov dl, [boot_drive]
    int 0x13
    ret

; ----------------------------
; CHS fallback path (AH=02h), one sector per request
; OUT: CF clear on success
load_kernel_chs:
    mov ah, 0x08
    mov dl, [boot_drive]
    int 0x13
    jc .fail

    xor ax, ax
    mov al, cl
    and al, 0x3f
    cmp al, 0
    je .fail
    mov [spt], ax

    xor ax, ax
    mov al, dh
    inc ax
    mov [heads], ax

    mov word [load_seg], KERNEL_LOAD_SEG
    mov dword [load_lba_low], 1
    mov cx, KERNEL_SECTORS

.next_sector:
    cmp cx, 0
    je .ok

    mov ax, [load_seg]
    mov es, ax
    xor bx, bx

    mov ax, [spt]
    xor dx, dx
    mov si, [load_lba_low]
    mov ax, si
    div word [spt]               ; AX=tmp, DX=sector-1
    inc dl                       ; sector in [1..spt]
    mov [chs_sector], dl

    xor dx, dx
    div word [heads]             ; AX=cylinder, DX=head
    cmp ax, 1023
    ja .fail
    mov [chs_cyl], ax
    mov [chs_head], dl

    mov byte [retry_count], 3
.retry:
    mov ah, 0x02
    mov al, 1
    mov ch, [chs_cyl]
    mov cl, [chs_sector]
    mov dl, [chs_head]
    shl dl, 6
    and dl, 0xC0
    or cl, dl                    ; cyl high bits in CL[7:6]
    mov dh, [chs_head]
    mov dl, [boot_drive]
    int 0x13
    jnc .read_ok

    call disk_reset
    dec byte [retry_count]
    jnz .retry
    stc
    ret

.read_ok:
    add word [load_seg], 0x20
    inc word [load_lba_low]
    dec cx
    jmp .next_sector

.ok:
    clc
    ret

.fail:
    stc
    ret

putc:
    push ax
    push bx
    mov ah, 0x0e
    xor bh, bh
    mov bl, 7
    int 0x10
    pop bx
    pop ax
    ret

; ----------------------------
; GDT and protected-mode entry
; ----------------------------
align 8
gdt_start:
    dq 0x0
gdt_code:
    dw 0xffff
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00
gdt_data:
    dw 0xffff
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

[bits 32]
init_pm:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov ebp, 0x90000
    mov esp, ebp

    jmp KERNEL_ENTRY

[bits 16]
boot_drive db 0
retry_count db 0

load_seg    dw KERNEL_LOAD_SEG
load_lba_low  dd 1
load_lba_high dd 0

spt       dw 0
heads     dw 0
chs_cyl   dw 0
chs_head  db 0
chs_sector db 0

align 4
disk_packet:
    db 0x10
    db 0x00
    dw 1
    dw 0x0000
    dw KERNEL_LOAD_SEG
    dd 1
    dd 0

times 510-($-$$) db 0
dw 0xaa55
