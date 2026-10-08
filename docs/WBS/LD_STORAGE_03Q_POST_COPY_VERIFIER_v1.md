# LD-STORAGE-03Q — Independent post-copy verifier v1

## Purpose

Re-open a mounted-backup receipt in a separate process and independently verify the bytes it claims were preserved. This lane does not perform copy, repair, overwrite, or cleanup.

## Proven behavior

- Validates the consumed mounted-backup receipt against its closed schema.
- Recomputes SHA-256 for every source and destination row and checks both against the receipt's expected hash.
- Rechecks source/destination path containment, row statuses, copied/duplicate counts, and leftover `.legacy-doctor.partial` files.
- Emits `verified` only when all rows and counts independently agree; tampered source or destination bytes become `blocked`.

## Proof

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_post_copy_verifier_v1.ps1 -RepoRoot C:\dev\legacy-doctor
```

The proof first executes a one-file owned fixture, verifies it in a separate process, then mutates the source and proves the verifier rejects the stale claim without writing destination bytes.

## Boundary

This is independent verification of the mounted-file executor. It does not prove resume after interruption, a sealed portable backup set, raw-disk/optical sector verification, filesystem repair, or named-device conformance.
