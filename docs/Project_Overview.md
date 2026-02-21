# MINI-OS Project Overview

## Current Functional Slice

The implemented path is end-to-end:

- bootloader -> kernel -> shell -> filesystem -> persistent disk image

## Main Source Areas

- `OS_src/boot/`: real-mode boot code and PM transition path
- `OS_src/kernel/`: shell loop, drivers, utilities
- `OS_src/kernel/fs/`: filesystem logic
- `build/`: generated binaries and image
- `docs/`: documentation set

## Where to Read Next

- Architecture: `docs/Architecture.md`
- Build and run: `docs/Build_and_Run.md`
- Shell usage: `docs/Shell_and_Usage.md`
- Filesystem current implementation: `docs/Filesystem_Current.md`
- Filesystem design idea draft: `docs/DIY-FS.md`
- Real hardware guide: `docs/Real_Hardware_Guide.md`
- Limitations: `docs/Limitations_and_Roadmap.md`
