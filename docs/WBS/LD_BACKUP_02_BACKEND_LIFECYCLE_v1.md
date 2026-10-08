# LD-BACKUP-02 — Backend registry, jobs, retention, and upload v1

## Purpose

Turn the destination/workspace contract into a backend lifecycle a future nontechnical interface can call. This is owned scope under the approved `workflow.storage-recovery` ecosystem role.

## Operational path available now

1. `ld_backend_destination_registry_v1.ps1` stores an immutable reference to a managed destination profile and independently rechecks its schema, root, and SHA-256 whenever it is verified.
2. `ld_backup_job_v1.ps1` stores an immutable mounted-file-backup job. The job binds the source, workspace-manifest SHA-256, payload destination, bounds, and schedule policy into its deterministic ID.
3. Running the job invokes the existing mounted-media executor. Every source file is SHA-256 cataloged, copied through a partial file, verified before and after promotion, and re-read at the source. Existing identical files are reported as verified duplicates; collisions fail closed. The executor also rejects source/destination reparse-point paths, malformed expected hashes, and source escapes, and removes empty directories it created when a run rolls back.
4. `ld_backup_retention_v1.ps1` inventories workspace manifests and marks candidates using `keep last` and age rules. It never permanently deletes data. An explicitly selected manifest can be moved into the destination's reversible quarantine only when its expected SHA-256 matches.
5. `ld_verified_file_upload_v1.ps1` provides the first upload adapter for a local folder or mounted network share. It accepts only a file with an expected SHA-256, copies through a partial file, verifies both ends, refuses collisions, and never modifies the source.
6. `ld_backup_scheduler_v1.ps1` is a controlled foreground poller. It independently validates each job, evaluates `manual`, `on_connect`, and `daily` eligibility, and—only with `-Execute`—dispatches eligible jobs through the verified job runner.
7. `ld_backup_set_seal_v1.ps1` creates an immutable content seal for a managed workspace, and `ld_backup_set_verify_v1.ps1` independently verifies the seal after relocation. These are integrity/completeness records, not encryption, signatures, or cloud replication.

All state and run records use closed, versioned schemas. Dry-run remains the default; writes require `-Execute`.

## Schedule semantics

Jobs can record `manual`, `on_connect`, or `daily`. The foreground scheduler now evaluates these policies. `on_connect` requires an explicitly supplied connected source root and will not replay a completed job on the next poll. `daily` becomes eligible after 24 hours since the latest verified run. `manual` requires an explicit include flag. This version still does not silently install a Windows Scheduled Task or background service.

## Integrity and security boundary

SHA-256 receipts detect byte changes and bind jobs to workspace manifests. This proves content integrity in the tested local threat model. It is not encryption, user authentication, hardware-backed key storage, or a digital signature. Those protections require an explicit key-management and identity design; the UI must not label these local hashes as encrypted or authenticated backups.

## Proof fixture

`_selftest_ld_backup_backend_lifecycle_v1.ps1` exercises the complete fixture lifecycle with representative music and ROM-like bytes:

- create a managed file-backup workspace;
- register and verify its destination;
- enqueue an `on_connect` job and prove idempotent re-enqueue;
- execute a bounded backup and compare source/destination SHA-256 values;
- upload one verified artifact and refuse a deliberately wrong hash;
- produce a retention plan and move the selected workspace into verified quarantine.

## Deliberate limits

- `on_connect` and `daily` are stored policies, not an installed scheduler.
- The scheduler is foreground-only; an operating-system service/task and device-event subscription are still not installed.
- The working upload adapter targets a local directory or already-mounted network share; cloud credentials and provider APIs are not configured.
- Retention has no permanent-delete operation.
- Raw-disk and optical imaging retain their existing explicit executor paths; this job runner currently dispatches mounted file backups only.
- No canonical long-term-preservation ownership is claimed.
