# MINI-OS Shell and Usage

This document only describes shell behavior and day-to-day usage inside MINI-OS.

## 1. Shell Entry

After boot and filesystem bootstrap, MINI-OS enters a loop:

1. Print current path prompt (`cwd >`).
2. Read one command line from keyboard.
3. Parse up to three tokens (`cmd arg1 arg2`).
4. Dispatch command handler.

Main implementation:

- `OS_src/kernel/main.asm`
- `OS_src/kernel/shell.asm`

## 2. Command List

Supported commands:

- `help`
- `ls`
- `pwd`
- `cd <dir>`
- `mkdir <dir>`
- `touch <file>`
- `cat <file>`
- `edit <file>`
- `rm <path>`
- `mv <old> <new>`
- `format`

## 3. Command Behavior

### `help`

Prints command summary.

### `ls`

Lists entries in current directory.

Output format is currently:

- `- name (d)` for directory
- `- name (f)` for regular file

### `pwd`

Prints current absolute path.

### `cd <dir>`

Changes current working directory.

- supports absolute and relative paths
- supports `.` and `..`
- fails if target is missing or not a directory

### `mkdir <dir>`

Creates a directory at the target path.

### `touch <file>`

Creates an empty file at the target path.

### `cat <file>`

Prints file content.

Current practical behavior is single-sector content read path.

### `edit <file>`

Enters text input mode for a file.

- `Enter` inserts newline
- `Backspace` deletes one char
- `ESC` saves and exits

If file does not exist, the shell tries to create it first.

### `rm <path>`

Removes file or directory entry.

- root directory cannot be removed
- non-empty directory removal is denied

### `mv <old> <new>`

Renames or moves entry.

- supports cross-directory move
- destination must not already exist
- moving a directory into itself/subtree is rejected

### `format`

Reformats filesystem and resets cwd to root.

## 4. Typical Usage Flow

Example session:

1. `mkdir docs`
2. `cd docs`
3. `touch note.txt`
4. `edit note.txt`
5. `cat note.txt`
6. `mv note.txt note2.txt`
7. `ls`

## 5. Input Notes

Keyboard input is polling-based and uses a limited scancode map.

This may not match all host keyboard layouts.

Implementation:

- `OS_src/kernel/drivers.asm`

## 6. User-Facing Error Messages

Shell handlers map internal error codes to text messages, such as:

- `Entry not found.`
- `Entry already exists.`
- `Target is not a directory.`
- `Target is not a regular file.`
- `Directory is not empty.`
- `Invalid path or name.`
- `Invalid move target.`

These mappings are defined in:

- `OS_src/kernel/shell.asm`
- message constants in `OS_src/kernel/main.asm`
