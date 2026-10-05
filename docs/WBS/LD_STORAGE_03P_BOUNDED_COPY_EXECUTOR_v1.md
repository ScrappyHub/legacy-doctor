# LD-STORAGE-03P — Bounded copy executor v1

## Purpose

Prove the first self-owned production-shaped file-preservation executor for mounted storage. The executor is the existing `scripts/media/ld_mounted_media_backup_v1.ps1` path, exercised through a dedicated Storage-03 proof harness.

## Proven behavior

- Dry-run never writes destination payload bytes.
- Execution is bounded by file and byte caps and refuses a truncated catalog.
- Source files are SHA-256 hashed before copy, copied through a `.legacy-doctor.partial` file, hashed before promotion, promoted without overwrite, and rehashed at the destination and source after promotion.
- Matching destination bytes are reported as verified duplicates without a new write.
- Mismatched destination bytes, stale partial files, source/destination overlap, path escapes, reparse-point paths, and malformed expected hashes fail closed.
- The source remains unchanged; source writes are always false.
- A failed run removes files and empty directories created by that run. Pre-existing partial artifacts remain untouched and are reported as blockers.

## Proof

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_bounded_copy_executor_v1.ps1 -RepoRoot C:\dev\legacy-doctor
```

The green token is emitted only after the positive copy, independent hash checks, duplicate rerun, collision refusal, bound refusal, stale-partial refusal, source-stability check, schema validation, and PowerShell parse checks pass:

```text
LEGACY_DOCTOR_STORAGE03_BOUNDED_COPY_EXECUTOR_GREEN
```

## Boundary

This proves a controlled mounted-file fixture, not broad device conformance, raw-disk imaging, optical sector acquisition, resume after interruption, or a portable backup-set seal. Those remain 03Q–03T and WBS 4 onward. A fixture pass is not evidence that every iPod, DVD, ROM source, COS file, SATA disk, or NVMe device is available on a given host.
