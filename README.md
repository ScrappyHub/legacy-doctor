# Legacy Doctor

Legacy Doctor is a receipt-backed, non-destructive storage recovery and backup-preflight instrument for Windows.

The supported Storage-03 scope inventories visible storage, classifies backup candidates, evaluates destinations, builds bounded dry-run manifests, and blocks copy execution until its safety contract is satisfied.

## Current safety boundary

Legacy Doctor can perform an explicitly requested, bounded, hash-verified copy between non-overlapping mounted directories. It does not format disks, image disks, repair filesystems, mount or unmount volumes, use native mobile-device protocols, or modify source media.

The destination write probe is the one supported write operation. It creates a bounded temporary file at an explicitly selected destination, reads and hashes it, and deletes it.

Historical FAT32 formatting code remains in the repository for review history but is quarantined at runtime and cannot access a device.

## Storage-03 lanes

- Device inventory and mount-state observation
- Windows-exposed health signals without SMART claims
- Mounted-volume read sampling
- Backup-readiness and file-source planning
- Destination selection and bounded write probing
- Bounded dry-run enumeration and manifest construction
- Manifest verification, execution preflight, run contract, and executor guard

A bounded mounted-file backup executor is available for explicit source and destination directories. It defaults to dry-run, requires `-Execute` to write, refuses path overlap and existing destination files, blocks truncated catalogs, copies through temporary files, verifies SHA-256 before and after finalization, and never writes source files.

## Legacy-media compatibility

The mounted-media catalog can hash and classify readable files using bounded path and extension hints, including synthetic `iPod_Control`, `VIDEO_TS`, ROM-candidate, optical-image, audio, and opaque `.cos` fixtures. Its self-test also reproduces those fixture files into an isolated proof destination and verifies every destination SHA-256.

This proves the mounted-file catalog and bounded copy engine, not physical-device compatibility. Modern iPhone/iPad/iPod touch access, Apple backup integration, optical-drive validation, protected DVD handling, playlist reconstruction, and raw-device recovery remain separate unimplemented lanes. See `docs/proposals/LEGACY_MEDIA_COMPATIBILITY_MATRIX_v1.md`.

## Verification

Run the repository verification entry point from Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\verify_project_v1.ps1 -RepoRoot .
```

The same command runs from a clean Windows checkout in `.github/workflows/verify.yml`. Receipt-producing stages are consumed through the shared fail-closed validator in `scripts/storage/_lib_ld_receipts_v1.ps1`; duplicate, malformed, schema-mismatched, or undeclared top-level claims are rejected.

Storage discovery may be unavailable without sufficient Windows permissions. Unavailable state must be reported explicitly and must block execution; it must not be treated as an empty successful inventory.

## Evidence

Runtime receipts are written below `proofs/`. They are local evidence outputs and are not source files. Current receipts are producer claims; schema enforcement, durable hash chaining, and independent receipt verification are active hardening work.

## Status

Storage-03 is implemented through the blocked copy executor guard (`03N`). Unavailable-state propagation, closed top-level receipt schemas, negative safety tests, and unified local verification are in place. Clean-clone CI and independently validated, hash-chained receipts remain release-qualification work.

The proposed service identity and ownership boundary are documented under `docs/proposals` pending ecosystem approval.

The checked-in governance baseline intentionally remains `unclassified` until that proposal is approved and the ecosystem service map, registry, canonical integration document, and project contract are updated together.
