# LD-STORAGE-03K Copy Manifest Verifier v1

Status: first checkpoint.

This lane consumes copy manifest dry-run output and verifies manifest structure before any copy executor exists.

It verifies:
- source path is present
- source file exists
- source file size matches metadata
- destination relative path is safe
- destination path remains under destination root
- system disk warnings are carried
- skipped rows are preserved

It does not:
- copy files
- write destination data
- hash source file contents
- modify source volumes
- create backup sets

Next checkpoints:
- destination selector plus write probe join
- bounded copy executor later
