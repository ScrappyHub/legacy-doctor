# LD-STORAGE-03S — Backup-set seal and portable verification v1

## Proven boundary

03S creates an immutable seal over a managed workspace payload. The canonical seal contains the workspace-manifest SHA-256, relative payload paths, byte sizes, and SHA-256 content hashes. It is written through a `.partial` file and promoted without overwrite.

The independent verifier recomputes the seal hash, validates the workspace manifest, rehashes every payload file, and rejects missing, changed, extra, reparse-point, or partial files. A copied workspace can be verified by supplying its new workspace root because the seal binds relative payload content rather than machine-specific paths.

## Proof

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_RUN_legacy_doctor_backup_set_seal_v1.ps1 -RepoRoot C:\dev\legacy-doctor
```

The proof covers dry-run no-write behavior, immutable seal creation, independent verification, portable workspace verification, tampered bytes, and extra payload rejection.

## Boundary

The seal is an integrity and completeness record, not encryption, authentication, a legal chain-of-custody signature, or a cloud backup. Key management, signed case packets, and destination/filesystem conformance remain separate work.
