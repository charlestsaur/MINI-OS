# 32-bit Assembly OS: DIY File System Design Spec

## 1 Disk Layout

Assume standard **LBA mode** with **512-byte sectors**.

| Start LBA | Region | Length | Description |
| --- | --- | --- | --- |
| `0` | Bootloader | 1 sector | 16-bit real-mode code that loads the kernel and switches to 32-bit mode. |
| `1` | Kernel image | 100 sectors (reserved) | 32-bit kernel binary area. |
| `101` | Superblock | 1 sector | Global file system metadata. |
| `102` | Inode bitmap | 1 sector | Bitmap for inode allocation status. |
| `103` | Data bitmap | 8 sectors | Bitmap for data-block allocation status. |
| `111` | Inode array | 256 sectors | Inode metadata table. |
| `367+` | Data blocks | Remaining sectors | File payload blocks (text content). |

Capacity note:

- Inode bitmap size is 512 bytes = 4096 bits.
- Inode array size is 256 sectors * 512 bytes / 64 bytes = **2048 inodes**.
- Effective inode capacity should therefore be **2048** unless the inode array is expanded.

## 2 Core Data Structures (NASM style)

### 2.1 Superblock

```nasm
struc Superblock
    .magic           resd 1    ; For example 0x534F5359 ("SOSY")
    .inode_count     resd 1    ; Total inode count
    .data_blk_count  resd 1    ; Total data block count
    .inode_start_lba resd 1    ; Inode array start sector
    .data_start_lba  resd 1    ; Data area start sector
    .root_inode      resd 1    ; Root directory inode index
endstruc
```

### 2.2 Inode (64 bytes)

```nasm
struc Inode
    .type        resb 1        ; 0=free, 1=file, 2=directory
    .name        resb 27       ; File or directory name
    .size        resd 1        ; File size in bytes
    .start_block resd 1        ; First data block LBA
    .blocks_cnt  resd 1        ; Number of occupied blocks
    .parent      resd 1        ; Parent inode index (root points to itself)
    .reserved    resb 22       ; Padding to 64-byte alignment
endstruc
```

## 3 Critical Low-Level Interface: ATA PIO

In 32-bit protected mode you cannot use BIOS disk services, so disk I/O must go through ATA ports.

Minimal read flow (`LBA28`, one sector):

1. Wait until BSY=0.
2. Program sector count (`0x1F2` = 1).
3. Program LBA low/mid/high (`0x1F3..0x1F5`).
4. Program drive/head (`0x1F6`) with `0xE0 | (lba>>24 & 0x0F)`.
5. Send command `0x20` to `0x1F7`.
6. Poll status until DRQ=1.
7. Read 256 words from `0x1F0` (`rep insw`).

Write flow is identical, except command `0x30` and data transfer uses `rep outsw`.

## 4 File Editor and File System Interaction

### 4.1 Save file (`save_file`)

1. Scan inode bitmap for a free inode bit.
2. Scan data bitmap for enough free blocks.
3. Fill inode metadata in memory.
4. Commit changes:
   - Write text payload to allocated data blocks.
   - Write inode entry into inode array.
   - Update inode/data bitmaps.

### 4.2 List file tree (`ls`)

1. Traverse inode array.
2. Check inode `.type`.
3. If `.type` is file or directory, print `.name`.

Hierarchical paths are implemented with:

1. Directory entry blocks (name -> inode).
2. Inode `.parent` pointers for `..`, `pwd`, and move validation.

## 5 Implementation Guidance

1. Keep constants centralized and use strict sector-based APIs (`read_sector`, `write_sector`).
2. Validate `magic` on boot; if invalid, run `format`.
3. Use QEMU/Bochs first; avoid testing on physical storage during early development.
