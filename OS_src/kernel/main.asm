[bits 32]
[org 0x8000]

; ----------------------------
; Kernel entry and constants
; ----------------------------
VGA_BUFFER          equ 0xB8000
VGA_WIDTH           equ 80
VGA_HEIGHT          equ 25
VGA_ATTR            equ 0x0F

ATA_DATA_PORT       equ 0x1F0
ATA_SECTOR_COUNT    equ 0x1F2
ATA_LBA_LOW         equ 0x1F3
ATA_LBA_MID         equ 0x1F4
ATA_LBA_HIGH        equ 0x1F5
ATA_DRIVE_HEAD      equ 0x1F6
ATA_COMMAND_STATUS  equ 0x1F7

ATA_CMD_READ        equ 0x20
ATA_CMD_WRITE       equ 0x30

KBD_STATUS_PORT     equ 0x64
KBD_DATA_PORT       equ 0x60

%define FS_LAYOUT_CONST(name, value) name equ value
%include "OS_src/kernel/fs/layout.def"
%undef FS_LAYOUT_CONST
%if FS_SUPER_DIRTY_OFFSET + 4 > 512
    %error "superblock dirty field must fit in its sector"
%endif

%define SYSCALL_CONST(name, value) name equ value
%include "transport/lib/syscall.def"
%undef SYSCALL_CONST

FS_OK                equ 0
FS_ERR_NOT_FOUND     equ -1
FS_ERR_EXISTS        equ -2
FS_ERR_NOT_DIR       equ -3
FS_ERR_NOT_EMPTY     equ -4
FS_ERR_INVALID       equ -5
FS_ERR_NO_INODE      equ -6
FS_ERR_NO_DATA       equ -7
FS_ERR_IO            equ -8
FS_ERR_CORRUPT       equ -9
FS_ERR_PROTECTED     equ -10
FS_ERR_PATH_TOO_LONG equ -11
FS_ERR_WRONG_DEVICE  equ -12

FS_MAX_PATH          equ 127
FS_MAX_DEPTH         equ 32
FS_FAT_EOC           equ 0xFFFF
FS_MAX_FILE_SIZE     equ FS_DATA_BLOCK_COUNT * 512

APP_IMAGE_BASE       equ 0x00040000
APP_IMAGE_END        equ 0x00050000
APP_IMAGE_SIZE       equ APP_IMAGE_END - APP_IMAGE_BASE
APP_IMAGE_MAX_BLOCKS equ APP_IMAGE_SIZE / 512
APP_ARG0_ADDR        equ 0x0008E000
APP_ARG0_CAP         equ 0x50
APP_ARG1_ADDR        equ 0x0008E050
APP_ARG1_CAP         equ 0xB0
APP_ARGV_ADDR        equ 0x0008E100
APP_STACK_TOP        equ 0x0008F000

INODE_SIZE          equ 64
INODE_NAME_LEN      equ 27
INODE_TYPE_OFF      equ 0
INODE_NAME_OFF      equ 1
INODE_SIZE_OFF      equ 28
INODE_START_OFF     equ 32
INODE_BLOCKS_OFF    equ 36
INODE_PARENT_OFF    equ 40

DIR_ENTRY_SIZE      equ 32
DIR_ENTRY_INODE_OFF equ 0
DIR_ENTRY_TYPE_OFF  equ 4
DIR_ENTRY_NAME_OFF  equ 5
DIR_ENTRY_NAME_LEN  equ 27
FS_NAME_MAX         equ DIR_ENTRY_NAME_LEN - 1
DIR_ENTRIES_PER_BLK equ 16

BOOT_CODE_ADDR      equ 0x00007C00
BOOT_CODE_CHECK_LEN equ 256
BOOT_VOLUME_ID_ADDR equ BOOT_CODE_ADDR + FS_BOOT_ID_OFFSET
KERNEL_CODE_CHECK_LEN equ 64

BUF_SUPERBLOCK      equ 0x20000
BUF_BITMAP          equ 0x21000
BUF_SECTOR          equ 0x22000
BUF_TEXT            equ 0x23000
BUF_INODE           equ 0x24000
BUF_CMD             equ 0x25000
PATH_PARENT_BUF     equ BUF_TEXT
PATH_NAME_BUF       equ BUF_TEXT + 256
PATH_PART_BUF       equ BUF_TEXT + 512
PATH_OLD_NAME_BUF   equ BUF_TEXT + 544
PATH_NEW_NAME_BUF   equ BUF_TEXT + 576
FS_VISITED_BUF      equ BUF_TEXT + 1024
PATH_BUILD_BUF      equ BUF_TEXT + 1536

; The boot sector transfers control to the first byte of the kernel image.
; Keep an executable entry stub here; the globals below are data, not code.
kernel_image_entry:
    jmp kernel_start
%if kernel_image_entry != $$
    %error "kernel entry stub must be the first byte of the image"
%endif

cursor_row          dd 0
cursor_col          dd 0
tok_cmd             dd 0
tok_arg1            dd 0
tok_arg2            dd 0
cwd_inode           dd 0
cwd_path_len        dd 1
cwd_path            times 128 db 0
tmp_inode_idx       dd 0
tmp_data_lba        dd 0
tmp_parent_inode    dd 0
tmp_name_ptr        dd 0
tmp_child_inode     dd 0
tmp_child_data_lba  dd 0
tmp_new_parent      dd 0
tmp_entry_idx       dd 0
tmp_type            db 0
tmp_mv_old_parent   dd 0
tmp_mv_new_parent   dd 0
tmp_mv_old_path     dd 0
tmp_mv_new_path     dd 0
tmp_chain_block     dd 0
tmp_chain_next      dd 0
tmp_chain_count     dd 0
tmp_alloc_block     dd 0
tmp_old_entry_idx   dd 0
tmp_new_entry_idx   dd 0
tmp_cwd_affected    db 0
tmp_cat_block       dd 0
tmp_cat_remaining   dd 0
tmp_cat_blocks      dd 0
tmp_edit_length     dd 0
tmp_edit_old_blocks dd 0
tmp_edit_tail       dd 0
tmp_edit_error      dd 0
tmp_edit_detached   db 0
tmp_edit_allocated  db 0
tmp_run_path        dd 0
tmp_run_arg         dd 0
tmp_run_block       dd 0
tmp_run_blocks      dd 0
tmp_run_index       dd 0
saved_kernel_esp    dd 0
fs_mutation_active  db 0
fs_mutation_touched db 0
fs_io_poisoned      db 0
tmp_mutation_result dd 0

kernel_start:
    cli
    cld
    call vga_clear

    mov esi, msg_boot
    call vga_print

    call idt_init
    call fs_bootstrap
    cmp eax, FS_OK
    je .fs_ready
    cmp eax, FS_ERR_WRONG_DEVICE
    jne kernel_fs_fatal
    mov esi, msg_wrong_device
    call vga_print
    jmp kernel_fs_halt
.fs_ready:
    call fs_set_cwd_root

    mov esi, msg_ready
    call vga_print

shell_loop:
    mov esi, cwd_path
    call vga_print
    mov esi, msg_prompt_suffix
    call vga_print

    mov edi, BUF_CMD
    mov ecx, 127
    call kbd_read_line

    mov esi, BUF_CMD
    call shell_dispatch
    jmp shell_loop

kernel_fs_fatal:
    mov esi, msg_fs_fatal
    call vga_print
kernel_fs_halt:
    cli
    hlt
    jmp kernel_fs_fatal

%include "OS_src/kernel/idt.asm"
%include "OS_src/kernel/shell.asm"
%include "OS_src/kernel/fs.asm"
%include "OS_src/kernel/drivers.asm"
%include "OS_src/kernel/utils.asm"

; ----------------------------
; Strings
; ----------------------------
msg_boot           db "MINI_OS: booting kernel...", 10, 0
msg_mount_ok       db "MINI_OS: filesystem detected.", 10, 0
msg_format_ok      db "MINI_OS: format complete.", 10, 0
msg_wrong_device   db "MINI_OS: boot device does not match primary ATA master; writes refused.", 10, 0
msg_ready          db "MINI_OS: shell ready. Type 'help'.", 10, 0
msg_prompt_suffix  db " > ", 0

msg_ls             db "entries:", 10, 0
msg_file_prefix    db " - ", 0

msg_help           db "Commands: help, ls, pwd, cd <dir>, mkdir <dir>, touch <file>, cat <file>, edit <file>, rm <path>, mv <old> <new>, run <file>, format", 10, 0
msg_unknown        db "Unknown command. Type 'help'.", 10, 0
msg_not_found      db "Entry not found.", 10, 0
msg_not_file       db "Target is not a regular file.", 10, 0
msg_not_dir        db "Target is not a directory.", 10, 0
msg_not_empty      db "Directory is not empty.", 10, 0
msg_empty          db "(empty)", 10, 0
msg_exists         db "Entry already exists.", 10, 0
msg_no_inode       db "No free inode available.", 10, 0
msg_no_data        db "No free data block available.", 10, 0
msg_rm_deny        db "Cannot remove root, current directory, or its ancestor.", 10, 0
msg_invalid_path   db "Invalid path or name.", 10, 0
msg_mv_invalid     db "Invalid move target.", 10, 0
msg_fs_io          db "Filesystem I/O failed; filesystem writes are disabled.", 10, 0
msg_fs_corrupt     db "Filesystem metadata is corrupt.", 10, 0
msg_path_too_long  db "Path is too deep or too long.", 10, 0
msg_fs_fatal       db "MINI_OS: filesystem unavailable; system halted.", 10, 0

msg_usage_cd       db "Usage: cd <dir>", 10, 0
msg_usage_mkdir    db "Usage: mkdir <dir>", 10, 0
msg_usage_cat      db "Usage: cat <file>", 10, 0
msg_usage_touch    db "Usage: touch <file>", 10, 0
msg_usage_rm       db "Usage: rm <path>", 10, 0
msg_usage_mv       db "Usage: mv <old> <new>", 10, 0
msg_usage_edit     db "Usage: edit <file>", 10, 0
msg_usage_run      db "Usage: run <file>", 10, 0

msg_touch_ok       db "Created: ", 0
msg_mkdir_ok       db "Directory created: ", 0
msg_rm_ok          db "Removed.", 10, 0
msg_mv_ok          db "Renamed.", 10, 0
msg_edit_prompt    db "Editor mode: Enter=new line, ESC=save and exit.", 10, 0
msg_edit_ok        db "Saved.", 10, 0
msg_app_start      db "MINI_OS: launching app...", 10, 0
msg_app_finished   db "MINI_OS: app exited cleanly.", 10, 0
msg_run_too_large  db "Executable exceeds the 64 KiB application image region.", 10, 0
msg_run_bad_image  db "Executable metadata or FAT chain is invalid.", 10, 0
msg_run_arg_long   db "Executable path or argument is too long.", 10, 0

cmd_help           db "help", 0
cmd_ls             db "ls", 0
cmd_pwd            db "pwd", 0
cmd_cd             db "cd", 0
cmd_mkdir          db "mkdir", 0
cmd_cat            db "cat", 0
cmd_touch          db "touch", 0
cmd_rm             db "rm", 0
cmd_mv             db "mv", 0
cmd_edit           db "edit", 0
cmd_run            db "run", 0
cmd_format         db "format", 0
cmd_vedit          db "vedit", 0
str_vedit_bin_path db "/transport/build/apps/vedit.bin", 0
str_path_apps_prefix db "/transport/build/apps/", 0

str_readme_name    db "README.TXT", 0
str_readme_content db "Welcome to MINI_OS.", 10
                   db "This disk was initialized by the kernel formatter.", 10
                   db "Try: ls, mkdir docs, cd docs, touch note.txt, edit note.txt.", 10, 0
str_readme_len     equ ($ - str_readme_content - 1)

str_dot            db ".", 0
str_dotdot         db "..", 0
