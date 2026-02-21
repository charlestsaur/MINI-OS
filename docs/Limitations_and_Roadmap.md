# MINI-OS Limitations

This file documents current limitations only.

## Platform And Runtime

- Single-task execution model.
- No process isolation; everything runs with kernel privilege.
- No virtual memory or paging.
- No interrupt-driven scheduling.

## Filesystem And Storage

- Contiguous allocation model per inode.
- No journaling and no crash recovery.
- No standalone fsck/repair command.
- No file permissions model.
- No ownership metadata.
- No timestamp metadata.
- On-disk compatibility/version migration is not defined.

## Device And Driver Layer

- ATA PIO path is polling-based.
- Disk I/O helpers do not expose rich hardware error codes to shell-level logic.
- Keyboard input is polling-based with a limited scancode mapping.

## Robustness And Validation

- Consistency checks are limited to mount-time structure validation and selected runtime guards.
- Corrupted metadata outside currently checked paths may still cause undefined behavior.
- Recovery workflow after corruption is mostly reformat-centric.

## Testing And Tooling

- No automated end-to-end command regression suite.
- Build dependencies are simple and do not track full include graph changes.
- No formal compatibility test matrix for different emulators or hardware variants.

## Summary

The system is functional for its current personal-project scope, but reliability and fault tolerance remain limited.
Using it as an experimental environment is reasonable; using it as a trusted storage system is not.
