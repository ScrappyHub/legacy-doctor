# Legacy Doctor

Deterministic storage preservation and formatting instrument.

Legacy Doctor provides verifiable, reproducible, and deterministic device management and formatting capabilities for legacy and modern storage media.

---

## Core Principles

Legacy Doctor guarantees:

• deterministic execution  
• explicit operator authorization  
• reproducible device identity  
• append-only canonical receipts  
• standalone operation  

Legacy Doctor never performs destructive operations without explicit operator consent.

---

## Features

• deterministic device enumeration  
• deterministic device identity generation  
• controlled formatting workflows  
• append-only receipt emission  
• offline-first operation  

---

## Example Usage

List devices:


powershell.exe -File scripts\storage\ld_storage_v1.ps1 -RepoRoot . -Cmd list


Format device:


powershell.exe -File scripts\storage\ld_storage_v1.ps1 -RepoRoot . -Cmd format -DiskNumber 5 -Fs exfat -Label SDCARD -IUnderstand ERASE_DISK_5


---

## Output

Receipts stored in:


proofs/receipts/storage.ndjson


---

## Specification

See:

docs/SPECIFICATION.md

---

## Status

Tier-0 Alpha  
Deterministic core operational

---

## License

MIT License
