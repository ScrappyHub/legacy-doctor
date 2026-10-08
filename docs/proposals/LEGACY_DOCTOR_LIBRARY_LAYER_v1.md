# Proposal: Legacy Doctor library layer (DRAFT, not approved)

Status: draft for owner review. No code exists for this layer. Nothing here changes the approved `workflow.storage-recovery` layer.

## Goal
A 2026 take on the iTunes role: know every device and medium Legacy Doctor has seen, back up what mounts, keep a searchable library of what was recovered, and set up music players safely.

## Scope boundary
- Storage lanes (Storage-03) stay the only code that copies or writes bytes. The library layer reads receipts and manifests; it never writes to a device.
- Device setup (formatting, folder layout, player database) is a separate guarded stage. It stays disabled until a named device has a passing evidence record.
- Media that does not mount (VHS, optical, floppy) is acquired by its own lane first; the library only indexes the resulting image or files.

## Components
1. Device registry: one record per physical device (vendor/product id, serial, model, filesystem, size) built from `ld.device.profile.v1` receipts. Identity keys on USB serial where present.
2. Backup index: links each device to its sealed backup sets and their verification receipts.
3. Track catalog: artist/album/title/duration/hash from tags read from backed-up files (read-only), deduplicated by content hash.
4. Player profiles: per-model rules (FAT32 mass-storage players, iPod Shuffle 2G layout under `iPod_Control`, generic MP3 players). A profile is data, versioned, and cannot be applied without a plan receipt.
5. Setup stage (guarded): dry-run plan receipt, explicit execute flag, post-write verification, and refusal when the target is not the named device.

## Safety rules
- Read-only by default; every write has a plan receipt and an execute flag.
- Never overwrite a file whose bytes differ without quarantining it first.
- Floppy and failing media: read with retries and a sector map, never write back to the source.
- iPod database writing (iTunesDB) is out of scope until an evidence record shows a round trip on a real device.

## Evidence needed before build
- Named-device profile of the iPod Shuffle (currently not detected) and the USB stick.
- One real backup of each, with a sealed set and verification receipt.

## Open questions for the owner
- Desktop UI, or CLI plus generated HTML library views first?
- Which player models matter first beyond the iPod Shuffle?
