# Legacy Doctor Roadmap

The roadmap is governed by [LEGACY_DOCTOR_MASTER_WBS_v1.md](WBS/LEGACY_DOCTOR_MASTER_WBS_v1.md) and its acceptance gates by [LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md](DOD/LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md).

## Current position

| Workstream | Status |
|---|---|
| Foundation and receipt law | partial; reconciliation ongoing; every emitted receipt schema now has a closed schema file, enforced by `_selftest_ld_lane_conformance_v1` |
| Storage-03A–03N observation and safety gates | proven |
| Storage-03O negative bounded-copy dry-run harness | proven |
| Storage-03P0 positive ready-path fixture | proven isolated fixture |
| Storage-03P bounded mounted-file copy | proven controlled fixture; first named-device run: iPod Shuffle 2G, one verified backup of an empty-ish device (`docs/evidence/2026-10-07_ipod-shuffle-2g.md`); broader real-device conformance open |
| Storage-03Q post-copy verifier | proven controlled fixture; real-device conformance open |
| Storage-03R resume/idempotency | durable-prefix restart proven; 03R2 stale-partial recovery lane proven on synthetic prefix partials (verifier 36/36 on 2026-10-07); killed-process proof run and passed 2026-10-07 (local NTFS destination, 300 MB fixture, one run); intent journal and named-device evidence open |
| Storage-03S backup-set seal | proven controlled workspace; signing/encryption remain open |
| Storage-03T destination matrix | local-host matrix and refusal/unavailable states proven (verifier 36/36 on 2026-10-07); named-device and network matrix open |
| Capacity-integrity test (free space only) | lane and selftest proven against a simulated fake-capacity device and a real NTFS target (verifier 37/37 on 2026-10-07); first real-device run: iPod Shuffle 2G, 934 MiB of free space verified with 0 bad blocks (`docs/evidence/2026-10-07_ipod-shuffle-2g_capacity.md`); cannot detect fakes on occupied space |
| Raw/optical real-device matrix | partial/historic; current re-audit required |
| Filesystem-aware recovery | future |
| Repair/wipe | deferred safety-critical reconciliation |
| Dashboard/desktop product shell | future integration surface |
| Archive Recall/TRIAD contracts | future, optional, versioned |
| Public release | not done |

Evidence collection for the open hardware items follows `docs/USAGE/LEGACY_DOCTOR_HARDWARE_CONFORMANCE_RUNBOOK_v1.md`.

## Release order

1. Complete automatic interruption recovery and governed partial quarantine (03R). **Lane implemented (`LD_STORAGE_03R2`); killed-process proof (`scripts/test/proof_interruption_kill_v1.ps1`) passed 2026-10-07 on local NTFS; remaining: optional intent journal, named-device evidence.**
2. Complete the destination/filesystem matrix (03T). Local-host portion proven; named removable, network, optical, and encrypted destinations remain open.
3. Reconcile current-branch image, extraction, packet, and owned-media lanes. Raw and optical acquisition now have a fail-closed self-test; named-device conformance is still required.
4. Run named-device conformance from legacy USB/optical media through SATA/NVMe.
5. Build the nontechnical dashboard on top of settled receipts and schemas.
6. Package, install, and independently verify a clean release.

The service role is approved as `workflow.storage-recovery` (2026-10-05), so none of the items above is blocked on ecosystem classification.
