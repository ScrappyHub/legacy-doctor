# LD-STORAGE-03J Copy Manifest Dry-Run v1

Status: first checkpoint.

This lane consumes backup dry-run enumerator output and emits a copy manifest plan.

It does:
- convert enumerator samples into WOULD_COPY manifest rows
- create destination-relative paths
- preserve source drive, relative path, size, and last-write time
- carry system disk warnings forward
- carry source enumeration errors into skipped rows

It does not:
- copy files
- write destination data
- hash source file contents
- modify source volumes
- create backup sets

Next checkpoints:
- destination selector plus write probe join
- file copy manifest verifier
- bounded copy executor later
