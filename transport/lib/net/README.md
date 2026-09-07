# Network Library Boundary

Sources added to this directory are compiled with the modern-C library flags and are linked only into `ping`, `netcat`, and `ssh` applications.

Public headers added here must remain usable by applications compiled under strict C90.

Protocol implementation begins in Phase D after the Phase B platform services and Phase C raw-frame driver exist.
