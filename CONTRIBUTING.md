# Contributing

All contributions must preserve deterministic behavior and the fail-closed safety posture described in [SECURITY.md](SECURITY.md) and [docs/DOD/LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md](docs/DOD/LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md).

## Ground rules

- No nondeterministic behavior in canonical output. Timestamps, host names, and random values must be isolated as noncanonical metadata.
- Never mutate source media. A new write lane needs a contract, a closed schema, positive and negative proofs, and an explicit statement of what it does not prove.
- Unavailable state (missing permissions, unreadable device) must block execution. It is never an empty successful result.
- Receipts are read only through the shared validator in `scripts/storage/_lib_ld_receipts_v1.ps1`. Do not add ad hoc receipt parsers.
- Files are UTF-8 without BOM with LF line endings (see `.gitattributes`).
- Do not edit canonical or governance files (`project.contract.json`, `docs/canonical/`, `AGENTS.md`, `CLAUDE.md`) as part of ordinary work. Put proposed changes under `docs/proposals/`.

## Adding or changing a lane

A lane normally consists of all of the following, named consistently with existing lanes:

1. Implementation in `scripts/storage/` or `scripts/media/`.
2. A closed receipt schema in `schemas/` (root `additionalProperties: false`, every `required` property declared).
3. A self-test in `scripts/selftest/` covering positive and negative cases. Anything in `scripts/selftest/` is run by the verifier.
4. A runner `scripts/_RUN_legacy_doctor_<lane>_v1.ps1` if the lane is operator-facing.
5. A WBS document in `docs/WBS/` and updates to `docs/ROADMAP.md`, `docs/USAGE/`, and the README status when scope changes.

## Verifying your change

From Windows PowerShell at the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\verify_project_v1.ps1 -RepoRoot .
```

This is the same command CI runs on `windows-latest`. It must pass from a clean checkout, and it must not modify tracked files.

## Scratch files

One-off patch, rewrite, and clipboard helpers are not product code. Keep them under `scripts/_scratch/` (git-ignored) and do not commit them.

## Pull requests

Describe which lane and contract the change touches, what the new proof demonstrates, and what remains unproven. Keep changes focused; do not mix lane work with governance or documentation rewrites.
