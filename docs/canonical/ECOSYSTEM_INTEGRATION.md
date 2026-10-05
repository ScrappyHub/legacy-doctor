# Ecosystem Integration — legacy-doctor

## Canonical service identity

| Field | Value |
|---|---|
| Service ID | `legacy-doctor` |
| Canonical name | legacy-doctor |
| Ecosystem layer | `workflow.storage-recovery` |
| Standalone-first | `true` |

## Role

Receipt-backed, non-destructive storage recovery and backup instrument that inventories visible devices, classifies readable backup candidates, evaluates destinations, builds and verifies bounded manifests, and blocks unsafe execution until every copy condition is explicitly proven.

## This service owns

- Non-destructive Windows storage observation and explicit unavailable states
- Backup-readiness classification
- File-source planning and bounded dry-run enumeration
- Destination suitability, bounded destination write probes, and backup destination profiles and workspaces
- Copy-manifest construction and verification, execution preflight, run contracts, and executor guards
- Bounded hash-verified mounted-file copy between explicit non-overlapping directories, post-copy verification, restart idempotency, and backup-set seal
- Bounded read-only device imaging with pinned identity and verified restore into disposable files
- Local receipts describing observations, decisions, refusals, and bounded probe results

## This service does not own

- Storage formatting or filesystem repair
- Unbounded or implicit raw-device imaging or copying
- Destructive recovery, repair, wipe, or physical-device restore
- Native mobile-device protocols
- Long-term blob preservation, snapshot, and restore authority (archive-recall, triad)
- Identity, signing, consent policy, or ecosystem-wide trust decisions (neverlost, covenant-gate)

## Upstream services

- `archive-recall`, optional: integration only through explicit versioned packet contracts. Legacy Doctor is standalone-correct without it.

## Downstream consumers or operators

- Operators

## Contract families

- `receipt`
- `manifest`

## Integration rules

1. This repository must remain independently understandable, testable, buildable, and releasable.
2. Ecosystem integrations extend capability but do not replace standalone correctness.
3. Integrations use explicit, versioned schemas and receipts.
4. No undocumented database sharing, hidden filesystem coupling, or implicit trust is permitted.
5. Producer claims must be independently verified by the receiving boundary where verification is required.
6. Integration failure must not silently corrupt local authoritative state.
7. Missing upstream services must produce an explicit unavailable, unknown, deferred, or failed state according to the local contract.
8. This repository's current implementation must not be treated as the complete product definition.

## Authoritative ecosystem sources

- `C:\dev\_ecosystem\SERVICE_MAP.md`
- `C:\dev\_ecosystem\service.registry.json`
- `C:\dev\_ecosystem\AGENT_POLICY.md`
- `C:\dev\_ecosystem\SHARED_INVARIANTS.md`

## Change governance

Changes to this service's ecosystem role, ownership boundaries, upstream dependencies, or downstream responsibilities require:

1. A proposal under `docs\proposals`.
2. A documented compatibility impact.
3. Updated service-map and registry entries.
4. Updated positive and negative integration tests.
5. A new service-map receipt.
