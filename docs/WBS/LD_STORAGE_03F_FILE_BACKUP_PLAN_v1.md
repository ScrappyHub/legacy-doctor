# LD-STORAGE-03F File Backup Plan v1

Status: first checkpoint.

This lane is dry-run only.

It consumes backup readiness output and emits a file-backup plan for volumes that are marked READY_FILE_BACKUP.

It does not:
- copy files
- write destination data
- image disks
- format disks
- mount disks
- modify source volumes

It emits:
- source volume
- estimated required bytes
- include rules
- exclude rules
- destination requirement
- system disk warning
- skipped rows

Next checkpoints:
- destination selector v1
- file backup dry-run enumerator v1
- copy executor with receipts later
