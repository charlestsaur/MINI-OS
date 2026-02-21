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

FS_MAGIC            equ 0x534F5359          ; "SOSY"
FS_INODE_COUNT      equ 2048
FS_DATA_BLOCK_COUNT equ 4096
FS_SUPERBLOCK_LBA   equ 101
FS_INODE_BMAP_LBA   equ 102
FS_DATA_BMAP_LBA    equ 103
FS_DATA_BMAP_SECS   equ 8
FS_INODE_START_LBA  equ 111
FS_INODE_SECS       equ 256
FS_DATA_START_LBA   equ 367

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
DIR_ENTRIES_PER_BLK equ 16

BUF_SUPERBLOCK      equ 0x20000
BUF_BITMAP          equ 0x21000
BUF_SECTOR          equ 0x22000
BUF_TEXT            equ 0x23000
BUF_INODE           equ 0x24000
BUF_CMD             equ 0x25000
PATH_PARENT_BUF     equ BUF_TEXT
PATH_NAME_BUF       equ BUF_TEXT + 64
PATH_PART_BUF       equ BUF_TEXT + 128

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

kernel_start:
    cli
    cld
    call vga_clear

    mov esi, msg_boot
    call vga_print

    call fs_bootstrap
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

%include "OS_src/kernel/shell.asm"
%include "OS_src/kernel/fs.asm"
%include "OS_src/kernel/drivers.asm"
%include "OS_src/kernel/utils.asm"

; ----------------------------
; Strings
; ----------------------------
msg_boot           db "MINI_OS: booting kernel...", 10, 0
msg_mount_ok       db "MINI_OS: filesystem detected.", 10, 0
msg_format         db "MINI_OS: no filesystem found, formatting disk...", 10, 0
msg_format_ok      db "MINI_OS: format complete.", 10, 0
msg_ready          db "MINI_OS: shell ready. Type 'help'.", 10, 0
msg_prompt_suffix  db " > ", 0

msg_ls             db "entries:", 10, 0
msg_file_prefix    db " - ", 0

msg_help           db "Commands: help, ls, pwd, cd <dir>, mkdir <dir>, touch <file>, cat <file>, edit <file>, rm <path>, mv <old> <new>, format", 10, 0
msg_unknown        db "Unknown command. Type 'help'.", 10, 0
msg_not_found      db "Entry not found.", 10, 0
msg_not_file       db "Target is not a regular file.", 10, 0
msg_not_dir        db "Target is not a directory.", 10, 0
msg_not_empty      db "Directory is not empty.", 10, 0
msg_empty          db "(empty)", 10, 0
msg_exists         db "Entry already exists.", 10, 0
msg_no_inode       db "No free inode available.", 10, 0
msg_no_data        db "No free data block available.", 10, 0
msg_rm_deny        db "Cannot remove root directory.", 10, 0
msg_invalid_path   db "Invalid path or name.", 10, 0
msg_mv_invalid     db "Invalid move target.", 10, 0

msg_usage_cd       db "Usage: cd <dir>", 10, 0
msg_usage_mkdir    db "Usage: mkdir <dir>", 10, 0
msg_usage_cat      db "Usage: cat <file>", 10, 0
msg_usage_touch    db "Usage: touch <file>", 10, 0
msg_usage_rm       db "Usage: rm <path>", 10, 0
msg_usage_mv       db "Usage: mv <old> <new>", 10, 0
msg_usage_edit     db "Usage: edit <file>", 10, 0

msg_touch_ok       db "Created: ", 0
msg_mkdir_ok       db "Directory created: ", 0
msg_rm_ok          db "Removed.", 10, 0
msg_mv_ok          db "Renamed.", 10, 0
msg_edit_prompt    db "Editor mode: Enter=new line, ESC=save and exit.", 10, 0
msg_edit_ok        db "Saved.", 10, 0

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
cmd_format         db "format", 0

str_readme_name    db "README.TXT", 0
str_readme_content db "Welcome to MINI_OS.", 10
                   db "This disk was initialized by the kernel formatter.", 10
                   db "Try: ls, mkdir docs, cd docs, touch note.txt, edit note.txt.", 10, 0
str_readme_len     equ ($ - str_readme_content - 1)

str_dot            db ".", 0
str_dotdot         db "..", 0
