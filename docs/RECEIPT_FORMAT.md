# Legacy Doctor Receipt Format v1

Receipts are versioned JSON objects written as UTF-8 without BOM and LF line endings. Producer output is not trusted merely because it contains a success token; the receiving verifier must parse the declared schema, reject undeclared top-level properties, and recompute hashes over precisely defined bytes.

## Required receipt law

Every operation receipt declares:

- `schema` and matching `event_type`;
- `ok`, `availability`, and an explicit execution status;
- operation mode, destructive/write flags, and source-write truth;
- exact source, destination, device, or artifact identity where applicable;
- limits and authorization flags;
- blockers, decisions, and rows needed to explain the result;
- UTC creation metadata isolated from canonical decision content.

## Evidence rules

- SHA-256 is the default content hash.
- Stored hashes, counts, signatures, and state claims are recomputed by verifiers.
- Temporary outputs are verified before promotion.
- Partial outputs are removed or moved to recoverable quarantine.
- Append-only evidence is not rewritten in place.
- A receipt never claims encryption, signing, forensic certification, or source compatibility that its lane did not prove.

The shared validator is `scripts/storage/_lib_ld_receipts_v1.ps1`. Schemas are closed at the top level under `schemas/`. Runtime evidence belongs under ignored `proofs/` and is not product source.
