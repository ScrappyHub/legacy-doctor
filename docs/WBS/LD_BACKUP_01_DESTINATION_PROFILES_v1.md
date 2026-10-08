# LD-BACKUP-01 — Destination profiles and one-click workspace setup v1

## Purpose

Provide the backend contract that a future Legacy Doctor interface can call after a user chooses a backup destination. The interface does not construct paths, invent folder names, or infer whether an existing directory is safe.

This implementation falls under the approved `workflow.storage-recovery` role (destination profiles and workspaces are owned scope).

## One-click contract

`scripts/storage/ld_backup_one_click_setup_v1.ps1` coordinates two independently receipted phases:

1. `ld_backup_destination_setup_v1.ps1` validates and initializes a destination profile.
2. `ld_backup_workspace_v1.ps1` creates an isolated workspace for one device and backup identifier.

Dry-run is the default. `-Execute` is required before destination folders are created. Source media is never written.

Required UI inputs are:

- destination root;
- user-facing destination label;
- backup mode: `file_backup`, `disk_image`, `optical_image`, or `device_export`;
- displayed device name;
- SHA-256 device identity supplied by the discovery boundary;
- optional backup identifier. The backend generates a UTC identifier when omitted.

## Managed destination layout

```text
<destination>/
  .legacy-doctor/
    destination-profile.v1.json
  content/
    file-backups/
    disk-images/
    optical-images/
    device-exports/
  staging/
  upload-queue/
  receipts/
  quarantine/
    cleared-copies/
```

Each backup workspace is placed below its mode folder:

```text
<mode-folder>/<safe-device-name>--<identity-prefix>/<backup-id>/
  workspace.v1.json
  payload/
  metadata/
  receipts/
  logs/
```

Executors receive `payload_path`; they do not choose their own destination. Receipts and logs remain separated from backed-up bytes.

## Safety and lifecycle rules

- A nonempty directory without a valid destination profile is refused.
- Existing profiles and workspaces are schema-validated and independently rehashed before reuse.
- Profile IDs derive from the normalized local root, label, and layout version.
- Device folder names combine a bounded safe name with the first 12 characters of the device-identity SHA-256.
- Backup identifiers reject traversal and path-escape characters.
- Creation uses temporary manifests and promotes them only after schema validation.
- A failed new destination setup rolls back only directories created by that run and only while they contain no files.
- Clearing means moving an explicitly selected verified destination copy into `quarantine/cleared-copies`; source media is outside this contract.
- Upload adapters may consume only verified artifacts and must use `upload-queue`; no provider is silently selected.

## Frontend integration

The future setup button calls the one-click script first without `-Execute` and renders its planned paths and blockers. After the user confirms, it repeats the exact inputs with `-Execute`. A successful receipt returns all paths needed by file-backup, imaging, upload, and receipt viewers.

## Current non-claims

- No cloud provider or network credential is configured. The first verified adapter targets a local folder or mounted network share.
- Schedule policies are now persisted, but this version does not install or run an operating-system scheduler.
- Retention planning and reversible quarantine are implemented; permanent deletion is intentionally unavailable.
- No canonical long-term-preservation ownership is claimed.
- Destination creation does not itself copy source content.

The next backend layer is specified and proven in `LD_BACKUP_02_BACKEND_LIFECYCLE_v1.md`.
