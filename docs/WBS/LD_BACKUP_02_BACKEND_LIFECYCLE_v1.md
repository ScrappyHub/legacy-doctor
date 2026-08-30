# LD-BACKUP-02 — Backend registry, jobs, retention, and upload v1

## Purpose

Turn the destination/workspace contract into a backend lifecycle a future nontechnical interface can call. This remains a standalone local workflow proposal while the repository's canonical ecosystem role is `unclassified`.

## Operational path available now

1. `ld_backend_destination_registry_v1.ps1` stores an immutable reference to a managed destination profile and independently rechecks its schema, root, and SHA-256 whenever it is verified.
2. `ld_backup_job_v1.ps1` stores an immutable mounted-file-backup job. The job binds the source, workspace-manifest SHA-256, payload destination, bounds, and schedule policy into its deterministic ID.
3. Running the job invokes the existing mounted-media executor. Every source file is SHA-256 cataloged, copied through a partial file, verified before and after promotion, and re-read at the source. Existing identical files are reported as verified duplicates; collisions fail closed.
4. `ld_backup_retention_v1.ps1` inventories workspace manifests and marks candidates using `keep last` and age rules. It never permanently deletes data. An explicitly selected manifest can be moved into the destination's reversible quarantine only when its expected SHA-256 matches.
5. `ld_verified_file_upload_v1.ps1` provides the first upload adapter for a local folder or mounted network share. It accepts only a file with an expected SHA-256, copies through a partial file, verifies both ends, refuses collisions, and never modifies the source.

All state and run records use closed, versioned schemas. Dry-run remains the default; writes require `-Execute`.

## Schedule semantics

Jobs can record `manual`, `on_connect`, or `daily`. These are backend policies for the future service/UI. This version does not silently install a Windows Scheduled Task or background service. A foreground service can list eligible jobs and invoke the same verified runner without changing the job contract.

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
- The working upload adapter targets a local directory or already-mounted network share; cloud credentials and provider APIs are not configured.
- Retention has no permanent-delete operation.
- Raw-disk and optical imaging retain their existing explicit executor paths; this job runner currently dispatches mounted file backups only.
- No canonical long-term-preservation ownership is claimed.
