# LD-STORAGE-03N Blocked Copy Executor Guard v1

Status: first checkpoint.

This lane proves the future copy executor refuses to run unless the backup run contract allows execution.

It consumes:
- ld.device.backup_run_contract.receipt.v1

It blocks:
- contract not allowed
- missing explicit destination
- repo-root destination
- preflight not ready
- missing max files cap
- missing max bytes cap
- missing execute flag
- missing system disk confirmation

It does not:
- copy files
- write destination data
- hash source file contents
- create backup sets
- modify source volumes

This is a guard lane only. The bounded copy executor is still not implemented.
