# Legacy Doctor â€” Spec (Windows v1)

## 0. Status
This spec is authoritative for Legacy Doctor Windows v1.
Anything not explicitly specified is NOT guaranteed.

## 1. Purpose
Legacy Doctor is a governed snapshot + restore instrument designed to:
- capture system/library state into sealed artifacts,
- restore deterministically under policy constraints,
- emit cryptographic proof (manifests + transcripts) of what was captured/restored.

## 2. Scope (Windows v1)
In-scope:
- Windows-first snapshot/restore workflows.
- Governed artifact emission (manifest + checksums + optional signatures/encryption).
- Deterministic pipeline harness requirements (safe-run / safe-paste).
- Verification workflows that produce sealed proof artifacts.

Out-of-scope (Windows v1):
- Cross-platform capture/restore (planned: Linux v1, macOS v1).
- Claims of ""Macrium-grade"" equivalence unless explicitly implemented and tested.
- Guaranteed recovery from physical disk failure without redundancy/ECC (optional future work).

## 3. Definitions
- Snapshot: a capture of data + metadata into an artifact set.
- Restore: writing snapshot contents back to a target.
- Artifact: a sealed bundle containing payload + manifest + checksums (+ optional signature/encryption).
- Manifest: structured statement of what data should exist, including hashes and structure.
- Transcript: append-only event log describing what the tool did.
- Policy: constraints that define what operations are allowed and how.

## 4. Canonical requirements
- Deterministic operation: repeatable outputs with recorded non-deterministic inputs.
- No silent modification: failures are recorded and must not be reported as success.
- Restore gating: verify-before-activate where feasible.

## 5. Workflows (Windows v1)
Snapshot -> Verify -> Restore -> Verify
Each emits transcript + sealed integrity evidence.

## 6. Reliability roadmap (instrument-grade)
- Chunked hashing + Merkle root identity.
- Dual-path verification (block-level + semantic).
- Independent verifier implementations.
- Optional redundancy shards for recoverability.

## 7. Versioning
Artifact format is defined in docs/artifact-format-v1.md.