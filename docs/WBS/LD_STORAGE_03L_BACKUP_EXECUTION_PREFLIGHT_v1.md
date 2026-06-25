# LD-STORAGE-03L Backup Execution Preflight v1

Status: first checkpoint.

This lane joins destination selection, destination write-probe, and copy manifest verification before any copy executor exists.

It emits:
- READY_FOR_BOUNDED_COPY
- BLOCKED_INSUFFICIENT_SPACE
- BLOCKED_SOURCE_EQUALS_DESTINATION
- BLOCKED_DESTINATION_MISSING
- BLOCKED_DESTINATION_DRIVE_UNKNOWN
- BLOCKED_DESTINATION_WRITE_PROBE_FAILED
- BLOCKED_MANIFEST_INVALID
- SYSTEM_DISK_COPY_REQUIRES_EXPLICIT_CONFIRMATION

It does not:
- copy files
- create backup sets
- hash file contents
- format disks
- image disks
- modify source volumes

It may run the bounded destination temp write probe because that lane is explicit and receipt-backed.
