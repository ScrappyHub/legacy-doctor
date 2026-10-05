# Legacy Doctor Roadmap

The roadmap is governed by [LEGACY_DOCTOR_MASTER_WBS_v1.md](WBS/LEGACY_DOCTOR_MASTER_WBS_v1.md) and its acceptance gates by [LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md](DOD/LEGACY_DOCTOR_DEFINITION_OF_DONE_v1.md).

## Current position

| Workstream | Status |
|---|---|
| Foundation and receipt law | partial; reconciliation ongoing; every emitted receipt schema now has a closed schema file, enforced by `_selftest_ld_lane_conformance_v1` |
| Storage-03A–03N observation and safety gates | proven |
| Storage-03O negative bounded-copy dry-run harness | proven |
| Storage-03P0 positive ready-path fixture | proven isolated fixture |
| Storage-03P bounded mounted-file copy | proven controlled fixture; real-device conformance open |
| Storage-03Q post-copy verifier | proven controlled fixture; real-device conformance open |
| Storage-03R resume/idempotency | durable-prefix restart proven; automatic interruption recovery open |
| Storage-03S backup-set seal | proven controlled workspace; signing/encryption remain open |
| Storage-03T destination matrix | local-host matrix and refusal/unavailable states implemented, pending a clean verifier run; named-device and network matrix open |
| Raw/optical real-device matrix | partial/historic; current re-audit required |
| Filesystem-aware recovery | future |
| Repair/wipe | deferred safety-critical reconciliation |
| Dashboard/desktop product shell | future integration surface |
| Archive Recall/TRIAD contracts | future, optional, versioned |
| Public release | not done |

## Release order

1. Complete automatic interruption recovery and governed partial quarantine (03R). **Next; not started.**
2. Complete the destination/filesystem matrix (03T). Local-host portion implemented; named removable, network, optical, and encrypted destinations remain open.
3. Reconcile current-branch image, extraction, packet, and owned-media lanes. Raw and optical acquisition now have a fail-closed self-test; named-device conformance is still required.
4. Run named-device conformance from legacy USB/optical media through SATA/NVMe.
5. Build the nontechnical dashboard on top of settled receipts and schemas.
6. Package, install, and independently verify a clean release.

The service role is approved as `workflow.storage-recovery` (2026-10-05), so none of the items above is blocked on ecosystem classification.
