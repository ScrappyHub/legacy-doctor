# LD-STORAGE-03R — Resume and idempotency boundary v1

## Proven boundary

The mounted-file executor can restart from a durable promoted prefix: already verified destination files are independently rehashed and skipped, while missing files are copied and verified. A repeated completed run performs no new copy.

Stale `.legacy-doctor.partial` artifacts fail closed. Legacy Doctor does not silently delete or overwrite them. The proof explicitly clears the fixture partial as an operator decision before the recovery run.

## Proof

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_resume_idempotency_v1.ps1 -RepoRoot C:\dev\legacy-doctor
```

The green proof shows a 2-file durable prefix resumes as 2 verified duplicates plus 2 copied files, a stale partial blocks without producing a final file, explicit cleanup permits recovery, and a repeat is 4 duplicates with 0 copies.

## Remaining gap

Automatic process-interruption recovery and governed quarantine of stale partials are not claimed complete. They remain open for 03R/03S design and DoD review.
