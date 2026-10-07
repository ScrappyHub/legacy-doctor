# Evidence: iPod Shuffle (2nd generation), free-space capacity-integrity test

Device (make/model, bus, filesystem, capacity): same device as `2026-10-07_ipod-shuffle-2g.md` (USB mass storage, FAT32, label IPOD_SHUF, 1,013,964,800 bytes claimed, 1,013,432,320 bytes free). Windows volume health "Warning" at test time; the run used `-AcceptHealthWarning`.
Date and operator: 2026-10-07, Al (ran commands), receipts reviewed by Claude.
Repository commit: 113b92b (branch codex/storage03-scope-alignment, not pushed).
Verifier result (step 0): 37/37, LEGACY_DOCTOR_PROJECT_VERIFICATION_OK, run earlier on 2026-10-07.

Runs (lane `scripts/storage/ld_capacity_test_v1.ps1`, target E:\):
1. Dry run, 64 MiB: pass, dry_run_ready, no blockers.
2. Execute, 64 MiB: pass, executed_pass, 67,108,864 written and verified, 0 bad blocks, read-back with the file cache bypassed, cleanup ok.
3. Execute, full free space minus the 32 MiB reserve: pass, executed_pass, PASS_TESTED_REGION_VERIFIED. Planned and written 979,369,984 bytes (934 MiB), verified good 979,369,984, 0 bad blocks, no write error, cache bypassed, cleanup ok. Tested 96.59% of the claimed capacity. Elapsed about 11 minutes.

Receipts (SHA-256):
- proofs/receipts/capacity_test/capacity_test_20261007_173107_121.json bb3cdb07e219f53a6b93e159622a838f9847217cbf3e92a79825c6010f963e64
- proofs/receipts/capacity_test/capacity_test_20261007_214320_683.json 018654594b190d749225925ce5bc5d617906db6b591f488bac0d59f208afdd71

Observed failures and what they mean: none in the lane. The run printed only one progress line (at 512 of 934 blocks) over about 11 minutes, which looked like a hang; progress reporting was improved afterwards.

What this does NOT prove: the test covers free space only. About 3.4% of the claimed capacity (the 32 MiB reserve, filesystem overhead, and the few hundred KiB of existing files) was not tested, so a device that fakes only a small tail would not be caught. It does not explain the Windows health "Warning". It says nothing about audio playback, iPod database writing, other devices, or behavior after repeated rewrite cycles. It is consistent with a genuine device of about 1 GB; it is not a certification.
