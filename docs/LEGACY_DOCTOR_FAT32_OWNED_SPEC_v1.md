# Legacy Doctor FAT32 Owned Formatter Spec v1

**Status:** Locked Draft for Implementation  
**Workstream:** LD-STORAGE-02A  
**Scope:** Tier-0 standalone formatter/verifier path for FAT32 media larger than 32GB without relying on Windows formatter policy or third-party FAT32 formatter executables.

---

## 1. Purpose

Legacy Doctor must own FAT32 formatting for removable media so the instrument can prepare SD cards, USB media, and other removable storage deterministically, offline, and auditable under strict safety gates.

This owned formatter exists because Windows built-in formatting policy refuses FAT32 for volumes larger than 32GB even though FAT32 itself supports substantially larger media. Legacy Doctor must therefore implement its own deterministic partitioning, filesystem structure writing, and verification path.

This formatter is part of Legacy Doctor’s Tier-0 storage authority. It is designed for standalone use first and later integration with Archive Recall, Triad, and premium orchestration layers.

---

## 2. Tier-0 Contract

The owned FAT32 formatter must:

- run offline
- run under Windows PowerShell 5.1 with `Set-StrictMode -Version Latest`
- use deterministic UTF-8 no BOM + LF file writes
- require explicit destructive intent
- emit append-only deterministic receipts
- verify what it wrote before claiming success
- refuse system and boot disks
- support media larger than 32GB
- avoid dependency on Windows FAT32 formatting policy
- avoid dependency on third-party FAT32 formatting executables

---

## 3. Non-Goals

This work item does **not** yet include:

- exFAT owned formatter
- NTFS owned formatter
- GPT multi-partition authoring
- device-specific content loading
- premium curated load profiles
- Archive Recall packet export/import
- Triad restore execution
- repair of damaged FAT32 beyond verification signaling
- full library indexing and content fingerprinting

These remain later WBS items.

---

## 4. Command Surface

Initial recommended commands:

- `-Cmd plan-format-fat32-owned`
- `-Cmd format-fat32-owned`

If Legacy Doctor keeps a single `format` entrypoint, the equivalent explicit contract is:

- `-Cmd format`
- `-Fs fat32`
- `-Formatter owned`

Tier-0 preference is explicit command naming rather than hidden formatter selection.

---

## 5. Required Parameters

### 5.1 Plan Command

The non-destructive planning command must accept:

- `-RepoRoot`
- `-Cmd plan-format-fat32-owned`
- target selector:
  - `-DiskNumber <int>`, or
  - `-DeviceId <string>`
- `-Label <string>`

Optional later:

- `-ClusterKiB <int>`
- `-WhatIf`

### 5.2 Format Command

The destructive format command must accept:

- `-RepoRoot`
- `-Cmd format-fat32-owned`
- target selector:
  - `-DiskNumber <int>`, or
  - `-DeviceId <string>`
- `-Label <string>`
- `-IUnderstand "ERASE_DISK_<n>"`

Optional later:

- `-ClusterKiB <int>`
- `-AutoElevate`
- `-Plan`
- `-WhatIf`

---

## 6. Safety Law

No destructive action is permitted unless all of the following are true:

1. The process is elevated.
2. The target resolves to exactly one disk.
3. The target disk is not the boot disk.
4. The target disk is not the system disk.
5. The exact destructive token matches the selected disk number.
6. A deterministic plan object was successfully computed.
7. The disk is considered removable, or a later explicit override path exists.
8. The formatter has passed internal preflight validation for partition geometry and FAT32 layout.

Failures must be deterministic and auditable.

---

## 7. Partitioning Policy v1

The initial owned FAT32 formatter locks the following partitioning model:

- **Partition style:** MBR
- **Partition count:** 1
- **Partition type:** FAT32 LBA (`0x0C`)
- **Partition start:** LBA 2048
- **Alignment:** 1 MiB
- **Partition end:** remainder of disk after reserved non-partition metadata area
- **Active flag:** false

This keeps Tier-0 compatibility broad and implementation manageable.

---

## 8. FAT32 Profile v1

Initial owned FAT32 filesystem policy:

- **Bytes per sector:** 512
- **FAT count:** 2
- **Root directory cluster:** 2
- **FSInfo sector:** present
- **Backup boot sector:** present
- **Volume label:** FAT-safe, uppercase, max 11 chars
- **Volume serial:** deterministic, not time-derived

The formatter must calculate reserved sectors, FAT size, and total cluster count deterministically from the target media size and selected cluster size.

---

## 9. Cluster Size Rule v1

The initial deterministic cluster-size rule is:

- media up to 32 GiB: 16 KiB or 32 KiB depending on final geometry rules
- media above 32 GiB and up to 512 GiB: 32 KiB
- explicit override support may be added later but must remain deterministic and validated

For the canonical current 256GB SD card use case, Legacy Doctor must choose:

- **32 KiB clusters**

---

## 10. Deterministic Volume Label Rule

The label must be sanitized before write:

- uppercase only
- allowed chars: `A-Z`, `0-9`, `_`, `-`
- maximum length: 11
- if empty after sanitization, default to `SDCARD`

The written volume label and the post-format verification label must match the sanitized value.

---

## 11. Deterministic Volume Serial Rule

The volume serial must not use current time.

Initial rule:

- derive from SHA-256 over deterministic inputs:
  - formatter kind
  - target disk number
  - device id
  - partition start LBA
  - partition size LBA
  - sanitized label

Use the first 4 bytes of the hash as the FAT32 volume serial.

This guarantees stable output for identical inputs.

---

## 12. On-Disk Structures To Write

The formatter must write and verify:

1. MBR sector
2. Primary FAT32 boot sector
3. FSInfo sector
4. Backup boot sector
5. FAT #1
6. FAT #2
7. Root directory cluster initialization

The formatter must not claim success unless these structures are written and verified.

---

## 13. Verification Contract

After writing, the formatter must re-read the disk and verify:

### 13.1 MBR

- final signature is `0x55AA`
- partition entry exists
- partition type is `0x0C`
- partition start LBA matches plan
- partition size LBA matches plan

### 13.2 Boot Sector

- jump field valid
- bytes per sector = 512
- sectors per cluster = expected
- reserved sectors = expected
- FAT count = 2
- FAT size = expected
- root cluster = 2
- FSInfo location matches plan
- backup boot location matches plan
- boot signature valid

### 13.3 FSInfo

- lead signature valid
- structure signature valid
- trailing signature valid
- free and next-cluster fields acceptable

### 13.4 Backup Boot Sector

- exists at expected location
- matches primary boot sector where required

### 13.5 FAT Regions

- FAT #1 and FAT #2 exist
- reserved cluster entries valid
- root cluster initialized correctly

### 13.6 Root Directory Region

- cluster 2 readable
- optional label entry valid if present

---

## 14. Verification Reason Codes

The verify engine must emit deterministic reason codes including, at minimum:

- `FAT32_VERIFY_FAIL:MBR_SIGNATURE`
- `FAT32_VERIFY_FAIL:PARTITION_ENTRY`
- `FAT32_VERIFY_FAIL:PARTITION_TYPE`
- `FAT32_VERIFY_FAIL:PARTITION_START`
- `FAT32_VERIFY_FAIL:PARTITION_SIZE`
- `FAT32_VERIFY_FAIL:BOOT_SIGNATURE`
- `FAT32_VERIFY_FAIL:BOOT_BPS`
- `FAT32_VERIFY_FAIL:BOOT_SPC`
- `FAT32_VERIFY_FAIL:BOOT_RESERVED`
- `FAT32_VERIFY_FAIL:BOOT_FAT_COUNT`
- `FAT32_VERIFY_FAIL:BOOT_FAT_SIZE`
- `FAT32_VERIFY_FAIL:BOOT_ROOT_CLUSTER`
- `FAT32_VERIFY_FAIL:FSINFO_SIGNATURE`
- `FAT32_VERIFY_FAIL:BACKUP_BOOT`
- `FAT32_VERIFY_FAIL:FAT_MIRROR`
- `FAT32_VERIFY_FAIL:ROOT_CLUSTER`

Success token:

- `FAT32_VERIFY_OK`

---

## 15. Receipt Model

Receipts append to:

- `proofs\receipts\storage.ndjson`

The owned FAT32 formatter must emit at least three receipt action types.

### 15.1 Plan Receipt

**Action:**

- `plan-format-fat32-owned`

**Fields include:**

- schema
- host
- time_utc
- target disk number
- device id
- disk size bytes
- partition style
- partition start LBA
- partition size LBA
- bytes per sector
- sectors per cluster
- reserved sectors
- FAT count
- FAT size sectors
- root cluster
- sanitized label
- formatter = `owned`
- ok

### 15.2 Format Receipt

**Action:**

- `format-fat32-owned`

**Fields include:**

- everything from plan
- execution start and end timestamps
- result expected filesystem = `FAT32`
- verification token
- verification summary
- receipt hash

### 15.3 Failure Receipt

**Action:**

- `format-fat32-owned-fail`

**Fields include:**

- target identifiers
- stage
- reason_code
- ok = false

---

## 16. Implementation WBS

### LD-STORAGE-02A.01 — Spec Lock

**Status:** RED

**Deliverables:**

- `docs/LEGACY_DOCTOR_FAT32_OWNED_SPEC_v1.md`
- locked geometry rules
- locked receipt fields
- locked verification reason codes

### LD-STORAGE-02A.02 — Raw Disk I/O Helpers

**Status:** RED

**Deliverables:**

- raw read helper
- raw write helper
- bounds-checked sector access
- admin gate
- deterministic byte helpers

**Notes:**

- no writes unless destructive token already validated

### LD-STORAGE-02A.03 — MBR Writer

**Status:** RED

**Deliverables:**

- deterministic MBR generation
- partition entry generation
- read-back verification

### LD-STORAGE-02A.04 — FAT32 Layout Calculator

**Status:** RED

**Deliverables:**

- cluster sizing
- reserved sector count
- FAT size computation
- total cluster count validation

### LD-STORAGE-02A.05 — FAT32 Structure Writer

**Status:** RED

**Deliverables:**

- boot sector
- FSInfo sector
- backup boot sector
- FAT #1
- FAT #2
- root cluster initialization

### LD-STORAGE-02A.06 — Verify Engine

**Status:** RED

**Deliverables:**

- read-only verifier for MBR and FAT32 layout
- deterministic reason codes
- success and failure tokens

### LD-STORAGE-02A.07 — Plan Command

**Status:** RED

**Deliverables:**

- non-destructive planning path
- plan receipt
- no mutation

### LD-STORAGE-02A.08 — Format Command

**Status:** RED

**Deliverables:**

- destructive owned formatter
- internal verify-after-write
- receipts
- final success token

### LD-STORAGE-02A.09 — Safe Selftest

**Status:** RED

**Deliverables:**

- disposable target workflow
- no default destructive selftest against live media
- deterministic PASS/FAIL

### LD-STORAGE-02A.10 — Golden Vectors

**Status:** RED

**Deliverables:**

- expected MBR bytes
- expected boot sector bytes
- expected FSInfo bytes
- expected FAT initial entries
- negative corruption vectors

### LD-STORAGE-02A.11 — One Runner

**Status:** RED

**Deliverables:**

- parse-gates all relevant scripts
- runs safe vectors
- emits deterministic transcript
- prints `LEGACY_DOCTOR_FAT32_OWNED_ALL_GREEN`

---

## 17. Implementation Order

The locked implementation order is:

1. spec lock
2. raw read helpers
3. verifier-first read-only path
4. layout calculator
5. MBR writer
6. FAT32 structure writer
7. verify-after-write engine
8. plan command
9. disposable selftest
10. one runner
11. only then optional live-media usage

No live destructive formatting should be treated as product-complete before the verifier-first path exists.

---

## 18. Definition of Done

LD-STORAGE-02A is complete when:

- Legacy Doctor formats removable media larger than 32GB as FAT32 without Windows FAT32 policy or third-party FAT32 formatter executables
- formatting is deterministic and offline
- formatting is protected by explicit safety law
- written structures verify correctly after write
- receipts are append-only and deterministic
- safe disposable selftests pass
- one runner prints `LEGACY_DOCTOR_FAT32_OWNED_ALL_GREEN`

---

## 19. Strategic Boundary

Legacy Doctor is the storage authority.

Archive Recall integration is optional and downstream.

Triad integration is orchestration and restore policy, not raw formatting truth.

Premium and SaaS layers may curate and orchestrate device workflows, but the actual raw formatting and verification authority remains the local deterministic Legacy Doctor instrument.
