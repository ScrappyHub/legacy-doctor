# Proposal: Legacy Doctor service identity v1

Status: proposed; not yet canonical

## Proposed role

Legacy Doctor is a receipt-backed, non-destructive storage recovery and backup-preflight instrument that inventories visible devices, classifies readable backup candidates, evaluates destinations and dry-run manifests, and blocks unsafe execution until every copy condition is explicitly proven.

## Proposed ecosystem classification

- Service ID: `legacy-doctor`
- Proposed layer: `workflow.storage-recovery`
- Standalone-first: true
- Proposed upstream services: none required for standalone correctness
- Optional upstream integration: Archive Recall through explicit versioned packet contracts

This layer keeps Legacy Doctor downstream of Archive Recall, as already indicated by the ecosystem service map. Legacy Doctor coordinates bounded device-recovery observations and preflight decisions; it does not claim Archive Recall's foundational preservation, snapshot, integrity-verification, or restore ownership.

## Proposed ownership

Legacy Doctor owns:

- Non-destructive Windows storage observation and explicit unavailable states.
- Backup-readiness classification.
- File-source planning and bounded dry-run enumeration.
- Destination suitability and bounded destination write probes.
- Copy-manifest construction and verification.
- Backup execution preflight, run contracts, and executor guards.
- Local receipts describing observations, decisions, refusals, and bounded probe results.

Legacy Doctor does not own:

- Storage formatting or filesystem repair.
- Unbounded or implicit raw-device imaging. A bounded read-only imaging extension is proposed below but is not canonical ownership.
- Destructive recovery.
- Long-term blob preservation.
- Identity, signing, consent policy, or ecosystem-wide trust decisions.
- An unbounded or implicit backup executor.

## Safety boundary

Supported lanes do not modify source media. The mounted-media backup lane may copy a bounded catalog into an explicit, non-overlapping destination after a write probe. It refuses existing destination files, verifies temporary and finalized SHA-256 values, and rolls back files created by a failed run. A proposed bounded imaging extension now pins device identity and exact size, excludes boot/system and same-disk targets, verifies source/image/source-re-read SHA-256, and validates rollback only into a disposable file. Read-only drive-letter planning is also implemented without an assignment path. These extensions do not change the canonical `unclassified` role and require ecosystem approval before becoming owned scope. Device-protocol backup, physical-device restore, drive-letter assignment, and unbounded copying are not implemented.

Historical FAT32 formatter code is quarantined and is not a supported capability.

## Determinism boundary

Deterministic decisions and canonical content must be separated from noncanonical observation metadata such as timestamps, host paths, device enumeration numbers, and performance measurements. Current receipts are producer claims until independent validation and durable evidence chaining are implemented.

## Compatibility impact

- README and tests will treat destructive formatting as unavailable.
- Storage discovery failure will become an explicit unavailable state that blocks downstream execution.
- Existing Storage-03 schema identifiers remain versioned, but stricter validation may reject receipts previously accepted by existence-only gates.
- No approved ecosystem dependency direction changes until this proposal is reviewed and the service registry is updated.

## Approval requirements

Promotion to canonical status requires updates to the ecosystem service map and registry, canonical identity/current-state documents, positive and negative integration tests, and a new service-map receipt.
