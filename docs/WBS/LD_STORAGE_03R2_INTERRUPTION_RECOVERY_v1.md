# LD-STORAGE-03R2 — Stale-partial recovery v1

## Boundary

`scripts/storage/ld_storage03_interruption_recovery_v1.ps1` classifies each `*.legacy-doctor.partial` file under a destination root against the source root, and, only with `-RecoverStalePartials -Execute`, moves recoverable partials into `<destination>/quarantine/stale-partials/<run id>/` by rename. It never deletes, rewrites, or reuses a partial, and it does not copy. After recovery the normal bounded executor (`ld_mounted_media_backup_v1.ps1`) completes the copy from the source.

A partial is **recoverable** only when all of these hold: the final file does not exist, the source file exists, the partial is not larger than the source, and the SHA-256 of the partial equals the SHA-256 of the same number of leading bytes of the current source file. Anything else (`FINAL_FILE_PRESENT`, `SOURCE_FILE_MISSING`, `PARTIAL_LARGER_THAN_SOURCE`, `PARTIAL_NOT_SOURCE_PREFIX`, `PARTIAL_OR_SOURCE_UNREADABLE`) is blocked. If any partial is blocked, nothing is moved.

Also blocked before enumeration: missing source or destination, source/destination overlap, a destination that is or contains the repository (except under `proofs\selftest`), and `-Execute` without `-RecoverStalePartials`. `-RecoverStalePartials` without `-Execute` is a dry run that reports the plan.

After each move the quarantined bytes are rehashed and compared with the pre-move hash and the origin is checked to be empty; on any failure the lane rolls back the moves it made and reports the failure.

Receipt: `ld.device.storage03_interruption_recovery.receipt.v1` (closed schema), with per-file classification, reason, hashes, and quarantine path.

## Proof

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_interruption_recovery_v1.ps1 -RepoRoot C:\dev\legacy-doctor
```

The self-test covers a dry run, a missing flag, quarantine with matching bytes, a byte-identical copy after recovery, a no-op replay, and eight blocking cases that leave every partial untouched.

## Killed-process proof

`scripts/test/proof_interruption_kill_v1.ps1` force-kills the real executor while a partial exists and runs the full block, recover, copy, and replay sequence on the result. It is timing-dependent and writes a large fixture, so it is not in the unified verifier. Procedure and expected tokens: `docs/USAGE/LEGACY_DOCTOR_HARDWARE_CONFORMANCE_RUNBOOK_v1.md`. Until it has been run and its result recorded, the real-interruption gate is open.

## What this does not prove

A prefix of the source proves the partial is consistent with an interrupted copy of that file. It does not prove this tool wrote it, so the lane quarantines rather than deletes. The unified-verifier proof uses synthetic prefix partials; the killed-process proof above is separate. Power-loss durability, network shares, removable-media behavior, and a source that changed during a run are not covered. The intent journal in the proposal is deferred; it would let the executor record intent before writing and is not required by this lane.
