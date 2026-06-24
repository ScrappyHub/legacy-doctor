# LD-STORAGE-03G Destination Selector v1

Status: first checkpoint.

This lane is dry-run only.

It consumes file backup plan output and evaluates a candidate destination path.

It checks:
- destination exists
- destination drive can be resolved
- destination free space compared to required estimate
- source drive equals destination drive
- system-source same-drive warning

It does not:
- copy files
- write destination data
- create destination folders
- format disks
- image disks
- modify source volumes

Possible selector actions:
- READY_DESTINATION
- INSUFFICIENT_SPACE
- SOURCE_EQUALS_DESTINATION
- DESTINATION_MISSING
- DESTINATION_DRIVE_UNKNOWN
- DESTINATION_IS_SYSTEM_SOURCE
- DESTINATION_REVIEW

Next checkpoints:
- destination write probe with explicit temp-file receipt
- backup dry-run enumerator
- copy executor later
