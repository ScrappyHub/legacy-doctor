# Legacy Doctor Definition of Done v1

Legacy Doctor is not release-complete when a script exists or a synthetic happy path passes. A lane is done only when all applicable gates below are true.

## Lane completion gates

- Contract and closed schema exist.
- Canonical/noncanonical bytes and timestamps are defined.
- Positive proof exists for the claimed operation.
- Negative proof covers wrong source, wrong destination, privilege failure, stale state, collision, partial output, corruption, and unavailable hardware as applicable.
- Source mutation is impossible or explicitly authorized and independently receipted.
- Destination separation, free space, write probe, bounds, and overwrite policy are checked.
- Output bytes and metadata are independently rehashed after promotion.
- Replay, interruption, and idempotency behavior are proven.
- Receipt and artifact verification work from a clean process.
- Documentation states what the lane does not prove.

## Product release gates

- WBS 0–3 current proof is green.
- WBS 1 historic lanes are re-run on the current branch or explicitly marked deferred.
- At least one named legacy mass-storage device, one optical state, and one SATA/NVMe device have conformance evidence; unsupported states are still receipted.
- No system/boot disk can enter a write lane without separate authorization.
- No permanent deletion, repair, wipe, or device restore is advertised without a governed lane.
- Case packets and receipts reject tampering and stale manifests.
- Clean checkout verification passes without local proofs or untracked scratch files.
- User docs explain admin requirements, supported filesystems, unsupported protocols, rollback, quarantine, and recovery.
- Package contents, hashes, and release receipt are independently verified.

## Current status

The repository currently has Storage-03A–03S, 03R2 (synthetic partials plus one killed-process run on local NTFS, 2026-10-07) and local-host 03T proof for controlled mounted-file/workspace fixtures and is **not** release-complete. Interruption recovery on named devices and other filesystems, named-device 03T evidence, real-device conformance, and later execution/recovery/release gates remain open.
