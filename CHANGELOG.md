# Changelog

All notable changes are recorded here. Legacy Doctor is pre-release; no public release has been made.

## Unreleased

Storage-03 and verified backup work since Tier-0 (see `docs/ROADMAP.md` for current status):

- Storage-03A to 03N: inventory, mount state, health probe, read probe, backup readiness, file-backup plan, destination selector, destination write probe, bounded dry-run enumerator, copy manifest and verification, execution preflight, run contract, and blocked-copy executor guard.
- Storage-03O: negative bounded-copy dry-run harness.
- Storage-03P0, 03P, 03Q: isolated positive fixture, bounded mounted-file copy executor, independent post-copy verifier (controlled fixtures only).
- Storage-03R: durable-prefix restart and idempotency proof. Automatic interruption recovery remains open.
- Storage-03S: backup-set seal and portable verification.
- Backup destination profiles, one-click setup, workspace, backend lifecycle, retention, and scheduler state.
- Mounted legacy-media catalog and bounded verified mounted-media backup; device inspector; optical imaging and drive-letter planning; read-only device imaging and restore verification.
- Shared fail-closed receipt validator, closed top-level receipt schemas, unified verifier (`scripts/test/verify_project_v1.ps1`), and Windows CI (`.github/workflows/verify.yml`).
- Repository governance baseline: `AGENTS.md`, `CLAUDE.md`, `project.contract.json`, `docs/canonical/ECOSYSTEM_INTEGRATION.md`, `SECURITY.md`, `.gitattributes`.

Changed:

- FAT32 formatting code is quarantined at runtime and cannot access a device. The Tier-0 "deterministic formatting workflows" are no longer a supported capability.

- Service identity approved as layer `workflow.storage-recovery`; verifier, contract, canonical integration document, and ecosystem map and registry updated together.
- Closed schemas added for the hashed catalog and backup-set content bodies, raw-disk facts, and the quarantined FAT32 plan and verify documents.
- New self-tests: lane conformance (every lane has coverage, every emitted receipt has a schema, destructive primitives only behind the formatter quarantine) and fail-closed raw/optical acquisition.
- `scripts/_scratch/` is no longer tracked.

Open: Storage-03T named-device evidence destination matrix, real-device conformance, automatic interruption recovery, release packaging.

## v0.1.0 Tier-0 Alpha

Initial deterministic release.

- Deterministic device enumeration
- Deterministic formatting workflows (since quarantined, see Unreleased)
- Receipt emission
- Standalone operation
