# Legacy Doctor — Drive Doctor

Legacy Doctor is a standalone-first, receipt-backed storage diagnosis and preservation instrument for legacy units through modern SATA/NVMe media.

The authoritative product documents are:

- [Product specification](docs/SPECIFICATION.md)
- [Master WBS](docs/WBS/LEGACY_DOCTOR_MASTER_WBS_v1.md)
- [Definition of Done](docs/DOD/LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md)
- [Operator usage](docs/USAGE/LEGACY_DOCTOR_USAGE_v1.md)

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

A verified mounted-media fixture backup path is available for explicit source and destination directories. Storage-03P now proves the self-owned bounded mounted-file executor against a controlled fixture, 03Q independently re-verifies its completed receipt, 03R proves durable-prefix restart/idempotency, and 03S seals/verifies a portable workspace; automatic interruption recovery and broad real-device conformance remain open.

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

Storage-03 is proven through the negative dry-run harness (`03O`), isolated positive ready-path fixture (`03P0`), controlled bounded-copy executor proof (`03P`), independent post-copy verifier (`03Q`), durable-prefix restart/idempotency proof (`03R` boundary), and backup-set seal/portable verification (`03S`). Unavailable-state propagation, closed top-level receipt schemas, negative safety tests, scheduler/registry state, and unified local verification are in place. Automatic interruption recovery, named-device destination matrix (03T runs locally only), broad device conformance, and release packaging remain open.

The service identity and ownership boundary were approved on 2026-10-05 as layer `workflow.storage-recovery` (see `docs/proposals/LEGACY_DOCTOR_SERVICE_IDENTITY_v1.md`, `docs/canonical/ECOSYSTEM_INTEGRATION.md`, and `project.contract.json`).
