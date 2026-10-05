# Legacy Doctor Master Work Breakdown Structure v1

This is the official work breakdown for the Drive Doctor product. Each item must have an implementation contract, positive proof, negative proof, receipt, and documented compatibility boundary before it can be called complete.

## WBS 0 — Foundation and evidence law

- 0A product identity, ownership, and non-goals
- 0B closed schemas, deterministic bytes, receipt validation
- 0C clean runner, proof retention, and release evidence
- 0D capability matrix with proven/unavailable/planned truth labels

## WBS 1 — Preservation core reconciliation

- 1A device identity and inspection reconciliation
- 1B raw acquisition and image manifest reconciliation
- 1C independent image verification and corruption rejection
- 1D extraction and byte-range recovery
- 1E evidence/case packet build and tamper verification

Historic proof is evidence to re-audit, not automatic current release status.

## WBS 2 — Owned media preparation

- 2A deterministic FAT32 layout and image vectors
- 2B owned test-fixture application and verification
- 2C explicit destructive authorization, privilege, and rollback boundary
- 2D compatibility matrix for filesystems and media classes

## WBS 3 — Controlled file preservation

- 3A device inventory and 3B mount state
- 3C health probe and 3D read probe
- 3E backup readiness and 3F file-backup plan
- 3G destination selector and 3H destination write probe
- 3I bounded enumeration and 3J copy-manifest dry run
- 3K copy-manifest verification and 3L execution preflight
- 3M backup run contract and 3N blocked executor guard
- 3O bounded executor dry-run harness — **proven negative**
- 3P0 positive safe ready-path fixture — **proven isolated fixture**
- 3P bounded copy executor — **proven controlled mounted-file fixture; real-device matrix remains open**
- 3Q post-copy independent verifier — **proven controlled mounted-file receipt**
- 3R resume, interruption recovery, and idempotency — **durable-prefix restart/idempotency proven; automatic interruption recovery remains open**
- 3S backup-set seal and portable verification — **proven controlled workspace**
- 3T real destination/filesystem matrix — **local-host matrix and refusal/unavailable states implemented; named-device and network evidence open**

## WBS 4 — Real-device conformance

Named evidence lanes for iPod/MP3 mass storage, optical/DVD, removable media, SATA, NVMe, USB bridges, and privilege/unavailable states. No generic “supports all drives” claim is allowed.

## WBS 5 — Recovery and extraction

Verified-image browsing, filesystem-aware extraction, byte-range recovery, damaged-media behavior, and restored-byte verification.

## WBS 6 — Repair and remediation

Future and safety-critical. Preserve-first, explicit authority, source mutation warning, rollback/verification, and separate destructive receipts are mandatory.

## WBS 7 — Evidence packaging

Portable case manifests, hashes, operation chain, operator decisions, tamper rejection, and export/import verification.

## WBS 8 — Product shell

Nontechnical dashboard for connected devices, health, capacity, libraries, selection/skip rules, duplicates, destinations, progress, receipts, rollback/quarantine, and unavailable states. The UI cannot invent backend capability.

## WBS 9 — Ecosystem contracts

Optional Archive Recall and TRIAD adapters with versioned schemas. No hidden coupling and no transfer of ownership.

## WBS 10 — Release

Clean clone, dependency/install proof, packaged scripts, clean-state verification, device matrix, threat model, user documentation, rollback/uninstall, release hashes, and independent release receipt.
