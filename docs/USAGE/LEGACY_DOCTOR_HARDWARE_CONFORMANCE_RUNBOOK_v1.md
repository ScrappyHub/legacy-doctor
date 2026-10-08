# Legacy Doctor hardware conformance runbook v1

Purpose: collect the named-device evidence that the roadmap and Definition of Done still require (03T named destinations, WBS 4 real-device conformance, and the 03R2 killed-process proof). Nothing here may be summarized as "supports all drives". Each result is one named device or destination, one receipt set, and an explicit pass, blocked, or unavailable outcome.

## Rules

- Use disposable or fully backed-up media. Never run an `-Execute` lane against a device holding the only copy of valuable data. Source media is never modified by these lanes.
- Run from an elevated Windows PowerShell only when a lane states it needs administrator rights; record when it was missing.
- Never use the system or boot disk, the repository, or the source as a destination.
- Keep the receipts under `proofs/`. They are local evidence; copy the receipt files and their SHA-256 values into the evidence record below. Redact machine paths and serial numbers before sharing anything publicly (see `SECURITY.md`).
- An `unavailable` or `blocked` result is a valid, recorded outcome.

## 0. Prerequisite

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\verify_project_v1.ps1 -RepoRoot .
```

Must print `LEGACY_DOCTOR_PROJECT_VERIFICATION_OK` before any hardware run.

## 1. Killed-process proof for 03R2

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\proof_interruption_kill_v1.ps1 -RepoRoot .
```

Expected final line `LD_STORAGE03_INTERRUPTION_KILL_PROOF_OK`. It writes a 300 MB fixture under `proofs\selftest`, force-kills the executor while a `.legacy-doctor.partial` exists, and then proves block, recover, copy, and replay. `INCONCLUSIVE_COULD_NOT_KILL_MID_COPY` means the copy finished too quickly; rerun with `-FileMegabytes 1000`. `REAL_PARTIAL_NOT_RECOVERABLE` is a real finding and must be reported, not worked around. (The first run hit this because a killed copy leaves a full-size partial with a zero-filled tail; the lane now classifies that as `PREFIX_WITH_ZERO_FILLED_TAIL`.)

## 2. Destination matrix, named destinations (03T)

For each named destination (USB flash FAT32, USB flash exFAT, external NTFS drive, SMB share, optical-writer media if applicable, encrypted volume), with the destination mounted and empty:

```powershell
# write probe (creates, reads, hashes, deletes one bounded temporary file)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\storage\ld_destination_write_probe_v1.ps1 -RepoRoot . -DestinationPath <destination>

# bounded verified copy from a small fixture folder you control
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\media\ld_mounted_media_backup_v1.ps1 -RepoRoot . -SourceRoot <fixture folder> -DestinationRoot <destination> -MaxFiles 50 -MaxBytes 1073741824
# review the dry-run receipt, then repeat with -Execute
```

Also run the 03R2 plan against the destination after a deliberately interrupted copy (kill the executor as in step 1, but with this destination).

## 3. Source device classes (WBS 4)

Run, in order, only the lanes that fit the device class, and keep every receipt:

- Mounted readable mass-storage (iPod, MP3 player, USB drive): `scripts\media\ld_media_catalog_v1.ps1` and the mounted-media backup above.
- Optical: `scripts\storage\ld_optical_image_acquire_v1.ps1` dry run first; with media loaded, supply the exact device name, size, and media fingerprint from the dry-run receipt, then `-Execute`.
- Raw SATA/NVMe/USB-bridged disk: read-only imaging `scripts\storage\ld_raw_image_acquire_v1.ps1` with the exact disk number, size, serial, and a byte bound; dry run first. Needs an elevated shell.
- Drive-letter state: `scripts\storage\ld_drive_letter_plan_v1.ps1` (read-only; it never assigns a letter).

The Definition of Done requires at least one named legacy mass-storage device, one optical state, and one SATA/NVMe device with evidence.

## 4. Evidence record

Create one file per device under `docs/evidence/` named `<date>_<short-device-name>.md` with:

```text
Device (make/model, bus, filesystem, capacity):
Date and operator:
Repository commit:
Verifier result (step 0):
Lane, command, and outcome (pass / blocked / unavailable) for each run:
Receipt file names and SHA-256 values:
Observed failures and what they mean:
What this does NOT prove:
```

Then update `docs/ROADMAP.md` and `docs/DOD/LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md` to cite the record, scoped to that named device.
