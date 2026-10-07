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

## 5. Owned imaging and rollback
Owner decision (2026-10-07): fully owned. Legacy Doctor implements imaging itself and does not depend on Macrium Reflect or any other imaging product.
- Image format: an open, documented Legacy Doctor image container (versioned header, chunked data, per-chunk SHA-256, whole-image hash chain, source device identity, bad-sector map). Built on the existing raw and optical acquire and verified-image lanes. Documented in `docs/` so the images stay readable without Legacy Doctor.
- Verify, list, mount-read-only and restore lanes for that format, each with a plan receipt and execute flag.
- Reading images made by other products (for example Macrium) is a separate, later decision; it is not part of the owned core.
- Rollback: every write-capable lane keeps a pre-change manifest and a restore plan; rollback is its own receipt-backed lane with verification.

## 6. Owned archive container and extraction
Owner decision (2026-10-07): fully owned. No dependency on 7-Zip.
- Container v1: a Legacy Doctor archive built on the .NET compression already present in Windows PowerShell 5.1 (Deflate), with a manifest of paths, sizes and SHA-256 hashes, written to a new destination only. Refuses path traversal, absolute paths and reparse points; extraction verifies every hash.
- Standard ZIP read and write through the same code, because it comes with the platform.
- Formats that need their own decoders (7z/LZMA, RAR) are out of scope for v1. Adding one is a separate proposal because it is a large implementation with its own test burden.
- Receipt: `ld.archive.operation.receipt.v1`.

## 7. Product identity (UI phase, after the above lanes)
- Mascot: an original 8-bit doctor character, used as the app icon and system-tray symbol. It is new artwork, not a copy of an existing character.
- Animation: a doctor's-office scene where the doctor checks drives, with new drives plugged in as devices arrive and a state shown per drive (healthy, warning, failing). Animations are driven by receipts, never by guesses.
- Tray menu: attached devices, last backup, last health result, start a safe scan.
The UI reads receipts and calls existing lanes; it contains no copy, write or format logic of its own.

## Owner decisions recorded (2026-10-07)
- Imaging and archive features are fully owned, with no external tool dependency.
- Capacity test is free-space only; it cannot detect a fake on a full drive, and the receipt must say so.

## Order of work
1. Health check and capacity-test lanes with selftests (read-only first).
2. Benchmark lane.
3. Owned archive container with selftests on synthetic data.
4. Owned image container, verify and restore lanes.
5. Library layer (separate proposal).
6. UI, mascot and tray.
