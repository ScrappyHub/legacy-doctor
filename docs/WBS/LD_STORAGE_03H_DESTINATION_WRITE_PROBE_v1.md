# LD-STORAGE-03H Destination Write Probe v1

Status: first checkpoint.

This lane performs a tiny explicit destination write probe.

It:
- requires an existing destination directory
- creates one temporary probe file
- writes a fixed payload
- flushes the file
- reads the payload back
- verifies SHA-256
- deletes the temporary file
- records cleanup success

It does not:
- copy backup files
- image disks
- format disks
- modify source volumes
- create backup sets

This is the first explicit bounded write lane and is limited to destination temp-probe validation only.

Next checkpoints:
- backup dry-run enumerator
- destination selector plus write-probe join
- copy executor later
