# Proposal: Legacy Doctor Drive Doctor scope v1

Status: proposed; does not alter canonical ecosystem files.

## Proposed identity

Legacy Doctor would be classified as `foundation.storage-preservation-intake`, with standalone-first correctness and no required upstream services.

## Proposed responsibility

Legacy Doctor would own the storage-side decision and evidence chain from physical/protocol discovery through verified local preservation, extraction, and case packaging. It would not own Archive Recall's durable preservation repository, TRIAD's transactional restore, NeverLost identity/signing, Covenant Gate policy, or cloud storage.

## Self-owned capability policy

Missing capabilities are backlog items to build in this repository: bounded copy, post-copy verification, resume, backup-set seal, device conformance, recovery/extraction, and the operator shell. An unavailable third-party protocol must remain an explicit adapter boundary. The project must not claim a vendor's proprietary backup format, protected-data extraction, DRM bypass, or forensic certification without its own contract and proof.

## Compatibility promise

The public promise is capability-specific: “Legacy Doctor tells you what the connected media is, how risky it is to touch, which preservation path is safe, and what evidence proves the result.” It is not “supports every drive.”

Promotion requires a service-map proposal review, updated registry and project contract, compatibility impact documentation, integration tests, and a new service-map receipt.
