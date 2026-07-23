[bits 32]
[global _start]
[extern main]

_start:
    call main          ; Call C main function

    ; sys_exit (syscall 1)
    mov ebx, eax       ; status = return value from main
    mov eax, 1         ; sys_exit
    int 0x80           ; System call

.loop:
    jmp .loop
