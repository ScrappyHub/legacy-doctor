# Evidence: iPod Shuffle (2nd generation), mounted-media backup

Device (make/model, bus, filesystem, capacity): Apple iPod Shuffle, 2nd generation (USB vendor 05AC, product 1301, firmware 2.70 as reported by Windows), USB mass storage, FAT32, label IPOD_SHUF, 1,013,964,800 bytes. Windows reported volume health "Warning" at profile time; cause not investigated.
Date and operator: 2026-10-07, Al (ran commands), receipts reviewed by Claude.
Repository commit: d40e682 (branch codex/storage03-scope-alignment, not pushed).
Verifier result (step 0): 36/36, LEGACY_DOCTOR_PROJECT_VERIFICATION_OK, run earlier on 2026-10-07 before the profiler script was added (the profiler is under scripts/test and is not part of the verifier).

Runs:
1. Device profile (`scripts/test/probe_device_profile_v1.ps1`, read-only): outcome pass. Kind IPOD_MASS_STORAGE, 10 files, 401,619 bytes, no audio files. The `iPod_Control\Device\SysInfo` file was not present, so model detail came from Windows device records, not the device.
2. Mounted-media backup dry run (`scripts/media/ld_mounted_media_backup_v1.ps1`, source E:\, destination outside the repo): outcome pass, status dry_run_ready, 10 planned files, no blockers, writes_source false.
3. Mounted-media backup execute (`-Execute`): outcome pass, status executed_verified, copied 10, verified 10, 401,619 bytes, no blockers, destination SHA-256 equal to source for every file.

Receipts (SHA-256):
- proofs/device_profile/device_profile_20261007_144509.json caf9742b1d5e1f419f3788725739d9e5327f1e3be5e990bc4eb0f87ffa6ca277
- proofs/receipts/mounted_media_backup/mounted_media_backup_20261007_144621_631.json 7e95ae0f755386ba3d2587f65237e555cff5c2ac5ff687296cce8b13fde10a0e
- proofs/receipts/mounted_media_backup/mounted_media_backup_20261007_152355_000.json 1cbe7df125efe463c63eadade597a1583cfccc6f6474d0bbfc98b7f516ee7279

Observed failures and what they mean: the Shuffle was not detected on first attempts (it appeared only after it was replugged); Windows lists it as remembered-but-absent when not enumerated. No copy failures.

What this does NOT prove: it covers one mounted-media backup of an essentially empty device (no audio). It does not prove large-file or full-capacity behavior, interruption recovery on this device, restore to the device, iPod database writing, the cause of the Warning health flag, or behavior of any other iPod model or player.
