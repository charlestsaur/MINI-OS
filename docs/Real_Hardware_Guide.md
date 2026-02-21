# MINI-OS on Real Hardware

This guide explains how to boot MINI-OS from a real USB drive and how to debug the common case where QEMU works but a physical machine shows only a blinking cursor.

> [!CAUTION]
> MINI-OS uses a very primitive file system implementation and has known flaws (such as aggressive, brute-force disk read/write operations). Therefore, long-term use may increase hardware wear and tear.
>
> Apart from this, MINI-OS does not perform any destructive operations on the machine. Nevertheless, to prevent potential data loss or hardware damage, it is still recommended to run it on a non-critical machine.

## 1. Why QEMU Works but Hardware Fails

QEMU is predictable and usually emulates a legacy BIOS + IDE disk path. Real machines vary widely:

- Many systems default to UEFI-only boot.
- USB boot behavior differs by firmware vendor.
- Some firmware does not expose USB media as classic BIOS disk in the same way.
- CSM/Legacy Boot may be disabled.

MINI_OS currently expects a legacy BIOS-style boot flow.

## 2. Hard Requirements

Before testing on physical hardware, ensure all of the following:

1. Boot mode is Legacy BIOS or CSM (not UEFI-only).
2. Secure Boot is disabled.
3. USB drive is selected in legacy boot menu.
4. The image is written to the whole USB device, not to a partition.

## 3. Build and Prepare Image

Build from project root:

```bash
make clean
make
```

Output image:

- `build/mini_os.img`

## 4. Write Image to USB (Whole Device)

Warning: these commands destroy existing data on the target USB drive.

> [!CAUTION]
> Pay close attention to the hard drive serial number, otherwise you may irreversibly erase your system drive

### 4.1 macOS

List disks:

```zsh
diskutil list
```

Unmount target disk (example: disk4):

```zsh
diskutil unmountDisk /dev/disk4
```

Write image (raw device is faster):

```zsh
sudo dd if=build/mini_os.img of=/dev/rdisk4 bs=4m status=progress
sync
```

Eject disk:

```zsh
diskutil eject /dev/disk4
```

### 4.2 Linux

Identify device (example: /dev/sdb):

```bash
lsblk
```

Write image:

```bash
sudo dd if=build/mini_os.img of=/dev/sdb bs=4M conv=fsync status=progress
sync
```

Eject disk:

```bash
sudo eject /dev/sdb
```

### 4.3 Windows

Use a raw image writer (for example Rufus in DD mode, or Win32 Disk Imager), and write `build/mini_os.img` to the entire USB device.

## 5. Firmware (BIOS/UEFI) Settings Checklist

In firmware setup:

1. Disable Secure Boot.
2. Enable CSM/Legacy Boot.
3. Prefer Legacy USB boot path.
4. Temporarily disable Fast Boot.
5. Put USB device first in boot order (or use one-time boot menu).

If your machine is UEFI-only with no CSM support, this MINI_OS build will not boot directly.

## 6. Expected Boot Behavior

On successful boot you should see text similar to:

- `MINI_OS: booting kernel...`
- `MINI_OS: filesystem detected.` (or format message on first run)
- prompt like `/ >`

If you only see a blinking cursor, use the troubleshooting section below.

With the current rewritten bootloader, you may also briefly see single diagnostic characters:

- `E`: loader is using INT 13h extensions (EDD/LBA path)
- `C`: loader fell back to CHS path
- `F`: kernel loading failed and bootloader halted

## 7. Troubleshooting: Blinking Cursor Only

### 7.1 Most common causes

1. Booted in UEFI mode while image expects BIOS mode.
2. USB image written to a partition instead of whole disk.
3. Wrong target disk selected during `dd`.
4. Firmware silently rejects USB geometry/boot path.

### 7.2 Quick diagnosis steps

1. Rebuild and rewrite image from scratch.
2. Re-check boot mode is Legacy/CSM.
3. Try another USB port (prefer USB 2.0 port if available).
4. Try another USB flash drive model.
5. Use one-time boot menu and explicitly pick legacy USB entry.

### 7.3 Add a visible boot-sector heartbeat

If needed, add a single character print at the very top of `OS_src/boot/boot.asm` before disk read. If the character appears, stage-1 boot code is running and failure is later in the flow.

## 8. Real-Hardware Compatibility Notes (Current Project State)

- Kernel is loaded by BIOS INT 13h extended read from LBA 1.
- Disk I/O in protected mode uses ATA PIO ports (`0x1F0` range).
- This is ideal for emulators but may be unreliable on some modern USB boot paths.

## 9. Current Compatibility Boundary

At the current stage, this image should be treated as BIOS/CSM-oriented.

UEFI-only machines without CSM are outside the present supported path.
