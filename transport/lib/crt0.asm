[bits 32]
[global _start]
[extern main]

_start:
    ; User stack frame: [esp+0]=dummy ret, [esp+4]=argc, [esp+8]=argv
    mov eax, [esp + 4]
    mov ebx, [esp + 8]

    push ebx
    push eax
    call main          ; Call C main(argc, argv)

    ; sys_exit (syscall 1)
    mov ebx, eax       ; status = return value from main
    mov eax, 1         ; sys_exit
    int 0x80           ; System call

.loop:
    jmp .loop
