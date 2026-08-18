# LD-MEDIA-01 — Bounded Mounted-Media Backup v1

## Purpose

Copy a bounded catalog of readable ordinary files from an explicit mounted source directory to an explicit existing destination directory while preserving source bytes and independently verifying destination SHA-256 values.

## Preconditions

- Source and destination are explicit existing directories.
- Source and destination are neither equal nor nested within one another.
- Destination is not the repository root.
- Catalog does not exceed `MaxFiles` or `MaxBytes`.
- No planned destination or deterministic partial path already exists.
- `-Execute` is required for destination writes.
- The bounded destination write probe succeeds.

## Execution

For each catalog row in deterministic order:

1. Recompute the source SHA-256 before copying.
2. Copy to a `.legacy-doctor.partial` file with overwrite disabled.
3. Verify the partial-file SHA-256.
4. Move the verified partial to its final non-existing destination.
5. Recompute destination and source SHA-256 values.
6. Record the verified row result.

If a row fails, the executor removes the current partial and rolls back final files created by that run. It never deletes a pre-existing destination file.

## Proof boundary

The self-test executes real filesystem copies using synthetic, user-owned fixture bytes and verifies every destination independently. This proves the mounted-directory engine. Named physical devices, Apple-device protocols, optical hardware, protected content, and raw media require separate evidence lanes.
