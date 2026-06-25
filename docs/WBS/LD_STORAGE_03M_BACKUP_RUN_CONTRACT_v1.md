# LD-STORAGE-03M Backup Run Contract v1

Status: first checkpoint.

This lane defines the strict backup run contract before any bounded copy executor exists.

It requires:
- explicit destination path
- repo-root destination block
- preflight readiness
- explicit max files cap
- explicit max bytes cap
- explicit system disk confirmation when system disk rows are present
- explicit execute flag before future bounded copy can be allowed

It does not:
- copy files
- write destination data
- hash source file contents
- format disks
- image disks
- modify source volumes

This lane emits only a contract receipt for the future executor.
