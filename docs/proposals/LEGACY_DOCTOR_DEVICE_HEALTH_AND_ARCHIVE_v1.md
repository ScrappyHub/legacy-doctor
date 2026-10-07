# Proposal: device health, capacity-integrity testing, imaging and archive integration (DRAFT, not approved)

Status: draft for owner review. No code exists for anything below. Extends `LEGACY_DOCTOR_LIBRARY_LAYER_v1.md`.

## 1. Capacity-integrity test (H2testw-style)
Purpose: detect counterfeit or failing media that reports a larger size than it can store.
- Method: write deterministic, position-keyed test files into free space only (each block derived from its file index and offset, so wrap-around and duplicate-block fakes are detected), then read everything back and compare. Report real usable bytes, first bad offset, and per-region error counts.
- Safety: never overwrites or deletes existing user files; test files are named and tracked in the receipt; cleanup removes only files the run created, after verification; refuses a volume with a dirty/Warning health flag unless `-AcceptHealthWarning` is given; refuses system and fixed disks by default.
- Proof plan: a software fake-capacity simulator (a wrapper that aliases offsets past a real size) as the selftest fixture, in the unified verifier. A real counterfeit device is not available, so real-device evidence can only show the genuine-capacity pass case.
- Receipt: `ld.device.capacity_test.receipt.v1`.

## 2. Benchmarking
Sequential and random read/write throughput on a named device with explicit file sizes. Results are measurements with the conditions recorded (device, filesystem, cache state), not pass/fail claims. Receipt: `ld.device.benchmark.receipt.v1`. Write benchmarks use the same free-space-only rules as section 1.

## 3. Health checks
Read-only first: filesystem dirty flag, SMART where the bus exposes it (SATA/NVMe), surface read scan with retry map for failing media, and a per-device health history in the registry. The iPod Shuffle currently reports Windows health "Warning"; the first health check should explain that before anything is written to it. No repair or format without a plan receipt and explicit execute flag.

## 4. Floppy and failing media
Read with bounded retries and a sector map, image first, work from the image. Never write back to a source medium. Corrupted reads are recorded as such, never silently replaced.

## 5. Imaging, Macrium path and rollback
Existing lanes already acquire raw and optical images and restore image files. Proposed additions:
- Detect an installed Macrium Reflect and record its version; support verifying and listing a backup it produced by calling its own tooling. Legacy Doctor does not parse or write the proprietary image format itself. Whether "Macrium path" means this integration or something else needs the owner's confirmation.
- Rollback: every write-capable lane keeps a pre-change manifest and a restore plan; a rollback is its own receipt-backed lane with verification.

## 6. 7-Zip integration
Use an installed 7-Zip (`7z.exe`) as an external tool: detect path and version, never bundle or modify it, run with explicit arguments, and hash inputs and outputs. Archive and extract only into new destination folders; extraction verifies listed sizes and hashes; refuse path traversal entries. Receipt: `ld.archive.operation.receipt.v1`.

## 7. Product identity (UI phase, after the above lanes)
- Mascot: an original 8-bit doctor character, used as the app icon and system-tray symbol. It is new artwork, not a copy of an existing character.
- Animation: a doctor's-office scene where the doctor checks drives, with new drives plugged in as devices arrive and a state shown per drive (healthy, warning, failing). Animations are driven by receipts, never by guesses.
- Tray menu: attached devices, last backup, last health result, start a safe scan.
The UI reads receipts and calls existing lanes; it contains no copy, write or format logic of its own.

## Order of work
1. Health check and capacity-test lanes with selftests (read-only first).
2. Benchmark lane.
3. 7-Zip wrapper with selftests on synthetic archives.
4. Macrium detection and verification (after the meaning is confirmed).
5. Library layer (separate proposal).
6. UI, mascot and tray.

## Open questions for the owner
- Confirm what "Macrium path capabilities" should mean (use a Macrium install, or reproduce imaging features in Legacy Doctor).
- Approve the free-space-only rule for the capacity test, which cannot detect fakes on a full drive.
