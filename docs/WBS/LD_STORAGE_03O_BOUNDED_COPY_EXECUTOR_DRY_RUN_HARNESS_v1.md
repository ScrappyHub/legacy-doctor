# LD-STORAGE-03O — Bounded Copy Executor Dry-Run Harness v1

## Purpose

Close the gap between the Storage-03 blocked executor guard and a future ready-path executor without copying any source bytes.

## Contract

The harness calls the existing backup-run contract and blocked-copy guard against the repository root as an intentionally unsafe destination. It emits a closed receipt proving:

- one candidate row was evaluated;
- `would_execute_count` is zero;
- the row disposition is `WOULD_NOT_EXECUTE`;
- `performs_copy` and `writes_destination` are false;
- the guard did not authorize a future executor.

The harness itself is not a backup executor. Its only output write is the normal evidence receipt under `proofs`.

## Proof runner

Run:

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_bounded_copy_executor_dry_run_harness_v1.ps1 -RepoRoot C:\dev\legacy-doctor
```

The green token is emitted only after the runner parses both PowerShell files, confirms the schema exists, executes the selftest, and checks the receipt fields:

```text
LEGACY_DOCTOR_STORAGE03_BOUNDED_COPY_EXECUTOR_DRY_RUN_HARNESS_GREEN
```

## Boundary

This lane does not prove a positive ready path, real file copy, post-copy hashing, resume, or a real destination matrix. Those remain 03P0, 03P, 03Q, 03R, and 03T respectively.
