[bits 16]
[org 0x7c00]

; Target memory address for the kernel
KERNEL_OFFSET equ 0x8000
%ifndef KERNEL_SECTORS
KERNEL_SECTORS equ 32
%endif

start:
    ; 1. Initialize registers
    cli                     ; Disable interrupts
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00          ; Stack grows downwards from 0x7c00
    sti                     ; Enable interrupts

    mov [boot_drive], dl    ; Save the boot drive number passed by BIOS

    ; 2. Load kernel using LBA Extended Read (INT 13h AH=42h)
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, disk_packet     ; DS:SI points to the Disk Address Packet
    int 0x13
    jc disk_error           ; Jump if carry flag is set (read failed)

    ; 3. Prepare to enter 32-bit Protected Mode
    cli                     ; Disable interrupts (IDT is not yet set up for PM)
    lgdt [gdt_descriptor]   ; Load the GDT descriptor

    mov eax, cr0
    or eax, 0x1             ; Set the PE (Protection Enable) bit in CR0
    mov cr0, eax

    ; 4. Far jump to flush the pipeline and enter 32-bit mode
    ; 0x08 is the offset for the Code Segment in our GDT
    jmp 0x08:init_pm

; --- Disk Address Packet (DAP) ---
align 4
disk_packet:
    db 0x10                 ; Size of the packet (16 bytes)
    db 0x00                 ; Reserved (always 0)
    dw KERNEL_SECTORS       ; Number of sectors to read (provided by build)
    dw KERNEL_OFFSET        ; Target Offset
    dw 0x0000               ; Target Segment
    dq 1                    ; Starting LBA sector (Sector 1, immediately after boot sector)

disk_error:
    mov ax, 0x0e45          ; BIOS Teletype function to print 'E' (Error)
    int 0x10
    jmp $                   ; Halt execution

; --- GDT (Global Descriptor Table) ---
align 8
gdt_start:
    dq 0x0                  ; Null descriptor (required)

; Code Segment Descriptor
gdt_code: 
    dw 0xffff               ; Limit (0-15 bits)
    dw 0x0                  ; Base (0-15 bits)
    db 0x0                  ; Base (16-23 bits)
    db 10011010b            ; Access Byte (Present, Ring 0, Executable, Readable)
    db 11001111b            ; Flags (4KB granularity, 32-bit mode)
    db 0x0                  ; Base (24-31 bits)

; Data Segment Descriptor
gdt_data:
    dw 0xffff
    dw 0x0
    db 0x0
    db 10010010b            ; Access Byte (Present, Ring 0, Writable)
    db 11001111b
    db 0x0

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1 ; GDT Size (minus 1)
    dd gdt_start               ; GDT Physical Address

; --- 32-bit Protected Mode ---
[bits 32]
init_pm:
    ; Update segment registers to point to the Data Segment (0x10)
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Update stack pointer to a safe area in high memory
    mov ebp, 0x90000
    mov esp, ebp

    ; Jump to the kernel entry point
    jmp KERNEL_OFFSET

; --- Boot Sector Footer ---
boot_drive db 0             ; Variable to store the boot drive ID
times 510-($-$$) db 0       ; Padding to reach 512 bytes
dw 0xAA55                   ; Boot signature
