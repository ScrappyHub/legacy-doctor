# Proposal: Legacy untracked file disposition v1

Status: proposed; files preserved pending operator disposition

## Purpose

This proposal records why two pre-existing untracked files are not part of the supported Legacy Doctor Git surface. It does not delete, rewrite, or silently ignore either file.

## `lib/doctor-common.ps1`

Proposed disposition: quarantine from the product surface pending redesign or removal approval.

Reasons:

- No tracked script references the library.
- Its run identifiers include time, host name, and randomness without isolating those values as noncanonical metadata.
- Its JSON and append helpers use Windows PowerShell encodings that produce UTF-8 BOM and CRLF output, contrary to shared canonical-byte invariants.
- `Seal-Run` hashes the audit log and then appends `RUN_SEALED` to that same log, so the recorded hash does not describe the final audit bytes.
- It has no tests or versioned receipt/schema contract.

Promotion would require deterministic byte writers, a corrected sealing sequence, explicit canonical/noncanonical boundaries, schemas, and positive/negative tests.

## `scripts/_ld_rescore_and_stage_docs_v1.ps1`

Proposed disposition: treat as orphaned local migration tooling pending removal approval.

Reasons:

- Its required `scripts/pipeline_score_legacy_doctor.ps1` dependency is absent.
- It performs broad Git staging rather than a bounded product or verification operation.
- No tracked workflow or documentation references it.

Promotion would require restoring and verifying its dependency, narrowing its staging targets, and documenting an operator contract. Otherwise it should be removed in a separately approved cleanup.

## Compatibility impact

Neither file is required by the supported Storage-03 chain, the unified verifier, or clean-archive verification. Keeping them outside the committed product surface has no supported runtime compatibility impact.
