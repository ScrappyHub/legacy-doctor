# LD-STORAGE-03T — Destination/filesystem matrix v1

## Proven boundary

The matrix runs the real write probe and bounded mounted-file copier against a writable local destination, then proves fail-closed behavior for source overlap, repository-root destinations, and missing paths. It also records explicit `unavailable` states for network shares and FAT32 when those transports are not mounted in the proof host.

The matrix reports observed filesystem metadata when Windows exposes it. It does not infer support from a device name, and an unavailable row is not a support claim.

## Proof

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_storage03_destination_matrix_v1.ps1 -RepoRoot C:\dev\legacy-doctor
```

## Boundary

This proves the local-host and refusal/unavailable states only. Named removable FAT32/exFAT devices, SMB/NFS shares, optical targets, encrypted volumes, and cross-host/network reliability still require named destination evidence.
