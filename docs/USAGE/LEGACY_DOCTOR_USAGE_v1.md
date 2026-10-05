# Legacy Doctor Operator Usage v1

Legacy Doctor is preserve-first. The normal operator sequence is discover, inspect, assess, recommend, preserve, verify, extract, package, and only then consider intervention.

## Verify the checkout

From Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\verify_project_v1.ps1 -RepoRoot .
```

This is the authoritative local proof runner. It does not make a device safe merely because the command is green.

## Current Storage-03 observation flow

Use the existing lane runners in order:

```text
inventory → mount state → health probe → read probe → backup readiness
→ file-backup plan → destination selector → write probe
→ bounded enumeration → copy manifest → manifest verification
→ execution preflight → run contract → executor guard → 03O dry-run harness
→ 03P controlled bounded-copy proof
→ 03Q independent post-copy verification
→ 03R durable-prefix restart/idempotency proof
→ 03S backup-set seal and portable verification
```

The 03O proof runner is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_bounded_copy_executor_dry_run_harness_v1.ps1 -RepoRoot .
```

It intentionally copies nothing. A green result means the unsafe path is blocked, not that a real backup has completed.

The controlled 03P proof runner is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_bounded_copy_executor_v1.ps1 -RepoRoot .
```

It copies only an isolated owned fixture under `proofs\selftest`, then independently checks destination hashes, source stability, duplicate idempotency, collision refusal, bounds, and stale-partial refusal. It is not a claim that every connected device is ready.

The independent 03Q proof runner is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_post_copy_verifier_v1.ps1 -RepoRoot .
```

It rehashes a completed receipt in a separate process and rejects a deliberately tampered source.

The 03R boundary proof is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_resume_idempotency_v1.ps1 -RepoRoot .
```

It proves safe restart and repeat idempotency. Stale partial artifacts are blocked, not silently deleted; automatic interruption recovery is not yet advertised.

The 03S seal and verification proof is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_backup_set_seal_v1.ps1 -RepoRoot .
```

It seals relative payload paths and hashes, verifies a copied workspace, and rejects tampered or extra payload files. The seal is integrity evidence, not encryption or a signature.

## Destination/workspace setup

The one-click setup scripts can dry-run and then create an explicit managed destination/workspace. Always inspect the dry-run receipt before repeating with `-Execute`. Destinations must not be the source, the repository, or an unmanaged nonempty root.

The backend lifecycle scripts support destination registration, job policy, foreground scheduling, retention planning, reversible quarantine, and verified local/network-share upload. Cloud credentials, modern iPhone extraction, DRM bypass, and permanent deletion are not silently substituted.

## Media catalog, drive-letter plan, imaging, and restore-to-file

All four lanes are read-only against the source and write only receipts under `proofs/` or an explicit, non-overlapping destination.

```text
# Hash and classify a mounted readable device (bounded by file count and bytes)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\media\ld_media_catalog_v1.ps1 -RepoRoot . -SourceRoot E:\ -MaxFiles 1000 -MaxBytes 1073741824

# Plan, but never assign, a free drive letter (receipt reports assigns_drive_letter = false)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\storage\ld_drive_letter_plan_v1.ps1 -RepoRoot .

# Restore a verified image file to another image file; dry run unless -Execute is given
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\storage\ld_image_restore_file_v1.ps1 -RepoRoot . -SourceImage <image> -DestinationImage <new file> -ExpectedSha256 <sha256> -MaxBytes <bytes>
```

Raw and optical acquisition (`ld_raw_image_acquire_v1.ps1`, `ld_optical_image_acquire_v1.ps1`) require the exact device identity and size, a byte bound, and `-Execute`; without those they report a dry-run or blocked receipt. The shared verified-image library (`_lib_ld_verified_image_v1.ps1`) hashes the source, the temporary image, and the source again after the copy, and rolls back a failed run. Image restore targets a file only; it never writes to a physical device.

## Device classes

- A mounted readable filesystem may be cataloged and planned for file preservation.
- A questionable, unknown, or metadata-critical device should be preserved by a read-only image when the exact device identity, size, privilege, destination, and source-stability gates pass.
- An optical drive with no reliable length/fingerprint remains `unavailable` or `manual_review`; do not guess an image boundary.
- A missing drive letter is an observation state, not permission to assign one automatically.
- iPhones, MTP/PTP devices, VHS, and other protocol/signal sources require their dedicated adapter lanes; they are not ordinary drive letters.

## Safety rules

Do not use the repository root as a destination. Do not approve a system/boot disk because it is visible. Do not overwrite a destination file by default. Do not call a copy complete until destination bytes and source stability have been independently verified. Preserve the only copy before repair, formatting, wiping, or restore.

## Evidence

Receipts under `proofs/` are local run evidence. A receipt is a claim until its schema, hashes, source identity, and output bytes are independently rechecked. The UI must present `available`, `blocked`, `failed`, `waiting`, and `manual_review` states distinctly.
