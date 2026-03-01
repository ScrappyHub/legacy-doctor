# Legacy Doctor Specification

## Purpose

Legacy Doctor provides deterministic storage device management with verifiable receipts.

---

## Determinism Requirements

Legacy Doctor guarantees:

• identical device identity for identical hardware
• identical receipt generation for identical operations
• no nondeterministic behavior

---

## Receipt Format

Append-only NDJSON.

Each operation produces one receipt entry.

---

## Execution Model

Operator → command → execution → receipt emission

---

## Safety Guarantees

Legacy Doctor never formats system or boot disks.

Operator authorization required.

---

## Encoding Requirements

UTF-8 no BOM  
LF line endings  

---

## Cryptographic Identity

DeviceId derived using SHA-256 over stable device properties.
