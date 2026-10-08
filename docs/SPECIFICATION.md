# Legacy Doctor — Product Specification v1

Status: active working specification; release incomplete.

## Product identity

Legacy Doctor is a standalone-first, deterministic storage diagnosis, preservation-intake, acquisition, recovery-preflight, controlled-backup, verification, extraction, and evidence-packaging instrument for aging, removable, unknown, fragile, damaged, or modern storage media.

Its operating law is:

```text
observe → diagnose → assess risk → prescribe/plan → preserve first
→ verify independently → extract/recover → optionally intervene → receipt everything
```

Legacy Doctor must never repair, format, wipe, overwrite, or “fix” the only copy merely because a device is connected.

## Scope boundary

Legacy Doctor owns storage intake and preservation operations:

- device discovery, identity, partition/volume inventory, and mount truth;
- safe health and readability signals with explicit unavailable states;
- preservation recommendations and backup readiness;
- destination validation, bounded write probes, file-backup planning, and controlled copying;
- raw-disk and optical acquisition when source identity, size, privilege, and destination gates are proven;
- image manifests, independent verification, extraction, and case/evidence packaging;
- owned-media preparation only through separately governed destructive lanes;
- versioned receipts, manifests, hashes, refusal reasons, and proof runners.

Legacy Doctor does not own long-term content-addressed preservation repositories, global archive indexing, transactional device restore, identity issuance, consent policy, cloud storage, or certified forensic authority. Archive Recall and TRIAD remain optional future integration boundaries.

## Self-owned implementation law

The supported storage workflow must be implemented and testable inside this repository. It may use documented Windows primitives and hardware interfaces, but it must not silently depend on a proprietary backup application, a cloud account, an undocumented shared database, or an unverified external executor.

Where a protocol cannot be self-owned safely, the capability is an explicit adapter boundary with an unavailable state—not a false “supported” claim. This applies to modern iPhone/MTP/PTP devices, protected optical content, damaged filesystems, and vendor-specific metadata.

## Macrium-grade acceptance bar

“Macrium-grade” is an engineering target, not a current completion claim. A release-quality backup lane must prove:

- explicit source identity and destination identity;
- source/destination separation, free-space and write-probe checks;
- bounded file and byte limits;
- temporary-file promotion with no default overwrite;
- progress and durable run receipts;
- source stability checks and destination rehashing;
- duplicate detection, collision refusal, resume/idempotency, and restart recovery;
- partial-output cleanup or recoverable quarantine;
- independent manifest and backup-set verification;
- clear exclusion of system/boot media unless separately authorized.

## Forensic-adjacent evidence bar

Legacy Doctor is forensic-adjacent, not presently a certified forensic acquisition suite. Stronger evidence requires immutable or append-only receipts, independently recomputed hashes, pinned source identity, exact operation parameters, privilege/unavailability state, tamper rejection, and portable case packaging. Chain-of-custody policy, legal admissibility, write blockers, and laboratory certification remain outside the current claim unless separately proven.

## Compatibility target

Compatibility is earned by transport, operation, and proof level—not by detecting a device name.

| Class | Target operation | Truth today |
|---|---|---|
| Mounted NTFS/FAT/exFAT volumes | inspect, plan, bounded file preservation | fixture and Windows-observation lanes proven; broad hardware matrix pending |
| iPod-class USB mass storage | inspect, file preserve, read-only image | named hardware evidence exists; broader device matrix pending |
| DVDs/opaque optical media | mounted catalog or verified sector image | explicit empty/unavailable/media-fingerprint states proven; copy-protection bypass excluded |
| ROM, COS, audio, video libraries | classify and preserve accessible files | bounded fixture/catalog proof; semantic parsing is not implied |
| SATA/NVMe | identity, health/readability, file or raw preservation | preflight and raw-image lanes exist; broad real-device proof pending |
| Floppy, IDE/SCSI, cartridges, cameras, MTP/PTP, iPhone | adapter-specific intake | planned or unavailable unless named transport evidence exists |
| VHS/Video8/cassette/vinyl | capture-interface intake | outside block-storage lanes; future signal-capture adapter |

## Current truth

Storage-03A through 03S are proven in the current verification suite for their declared boundaries. 03O is the negative dry-run harness, 03P0 is an isolated positive guard fixture, 03P proves the self-owned bounded mounted-file executor against a controlled fixture, 03Q independently rehashes a completed mounted-backup receipt, 03R proves durable-prefix restart/repeat idempotency, and 03S seals and independently verifies a portable workspace payload. Automatic stale-partial/process-interruption recovery remains open. These fixture lanes are not broad real-device conformance. Destination matrix (03T), named-device evidence, signing/encryption, and legal chain-of-custody remain open. Historical imaging, extraction, packet, and FAT32 work must be re-audited on the current branch before being called release-green.

The master work breakdown, definition of done, and operator usage are authoritative in:

- `docs/WBS/LEGACY_DOCTOR_MASTER_WBS_v1.md`
- `docs/DOD/LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md`
- `docs/USAGE/LEGACY_DOCTOR_USAGE_v1.md`

The ecosystem service identity is layer `workflow.storage-recovery`, approved 2026-10-05 and recorded in `docs/canonical/ECOSYSTEM_INTEGRATION.md`.
