# Proposal: Legacy media compatibility and proof matrix v1

Status: proposed; mounted-media backup, physical read-only imaging, and restore-to-file lanes implemented

## Product goal

Legacy Doctor should preserve accessible user-owned content from legacy storage and device ecosystems while producing receipts that distinguish observed evidence from inferred format hints. A green test may claim only the lane it actually exercises.

## Current conflict requiring canonical review

`docs/SPECIFICATION.md` and `docs/ROADMAP.md` describe deterministic formatting as a product purpose. The supported Storage-03 implementation and the proposed service identity instead quarantine formatting and define a non-destructive recovery boundary. This proposal does not resolve that canonical/product-definition conflict; it requires operator and ecosystem review.

## Compatibility lanes

| Lane | Intended sources | Current proof level | Allowed claim | Explicit non-claim |
|---|---|---|---|---|
| Mounted-media catalog | Any readable mounted directory | Deterministic fixture and copy/hash proof | Files can be enumerated, classified by path/extension hints, hashed, and reproduced byte-for-byte by the fixture harness | No claim that arbitrary hardware mounts or that every file is semantically valid |
| Legacy iPod disk layout | Readable `iPod_Control` trees and Windows-exposed block device | Named Apple iPod hardware: mounted file backup plus 1,015,021,568-byte full-disk acquisition and restore-to-file proof | Accessible files and every physical-disk byte can be preserved read-only with matching SHA-256 source, source re-read, image, and disposable restore hashes | No iTunesDB interpretation, playlist reconstruction, repair, format, or device write support yet |
| iPhone, iPad, iPod touch | Apple Devices app / trusted Apple-device connection | Not implemented | Future adapter boundary only | No pairing bypass, protected-data extraction, sync, restore, or direct device backup claim |
| DVD-Video files and opaque game media | Readable mounted `VIDEO_TS` trees or raw optical media exposed by the drive | Synthetic layout/sector fixtures plus named MATSHITA evidence: empty state, inserted Wii Fit media, and approved raw probe | `.IFO`, `.BUP`, and `.VOB` files are preserved when mounted; opaque media proceeds only after exact raw length and sampled-byte fingerprint are available | The Wii Fit disc was not imaged because this reader returned `OPTICAL_LENGTH_UNAVAILABLE`; no playback validation, CSS/decryption, or copy-protection bypass |
| Optical images | User-accessible `.iso`, `.img`, `.nrg`, `.mdf` files | Synthetic file fixture | Files are preserved as opaque optical-image candidates | No filesystem mounting or image-content validation |
| ROM collections | User-accessible ROM-like files | Synthetic extension fixture | Files can be preserved and labeled as ROM candidates using bounded extension/path hints | No emulator, provenance, ownership, or playability claim |
| `.cos` artifacts | User-accessible `.cos` files | Synthetic extension fixture | Files can be preserved as opaque COS artifacts | No assumption about which COS format produced the file and no execution/parsing claim |
| Bounded mounted-file backup | Explicit readable source and existing destination directories | Deterministic execution fixture with destination SHA-256 verification | A bounded set of ordinary files can be copied without overwriting, with source/destination separation, temporary-file verification, and fail-closed receipts | Physical-device compatibility still requires named-hardware evidence; this is not raw imaging or a device-protocol adapter |
| Read-only full-disk acquisition | Windows physical disks with pinned disk number, serial, exact size, and different destination disk | Deterministic negative/positive fixtures plus named Apple iPod hardware | A non-boot, non-system block device can be captured exactly once into a temporary image, independently hashed, re-read for source stability, and promoted only when all hashes match | One iPod proves this named hardware path, not every USB, floppy, IDE, SCSI, SATA, or NVMe controller |
| Restore-to-file validation | Previously verified image files | Deterministic fixture plus the real iPod image restored into a disposable file | Rollback bytes can be reproduced into a non-device file with exact byte count and three matching SHA-256 observations | This is not authorization or proof for writing an image back to any physical device |
| Optical read-only acquisition | Windows optical volume or opaque raw media pinned by drive identity, sampled-byte fingerprint, exact size, and destination capacity | Deterministic 2048-byte-sector fixture; actual MATSHITA DVD-RAM UJ8C0 empty, inserted-media, and raw-length-unavailable states proven | The acquisition engine verifies source, source re-read, and destination image hashes; it reports empty, unmounted, unreadable, and incompatible-reader states without writes | This MATSHITA reader cannot establish a safe Wii Fit image boundary; a compatible reader or verified external dump is required |

## Content lifecycle boundary

Verified artifacts may be kept locally or passed to a future explicit upload adapter. Upload requires a user-chosen provider/destination and must preserve the content hash and receipt. Clearing is destination-scoped: only an explicitly selected backup copy may be removed after verification and separate approval. Source media, including pressed optical discs, is never treated as a clearable destination. Rewritable-media erasure would be a separate destructive capability with its own contract and is not implemented.

The implemented destination-profile extension gives the future interface one backend call for dry-run or confirmed setup. It creates a versioned managed root, mode-specific content folders, staging and upload queues, receipt storage, destination-copy quarantine, and isolated per-device workspaces. It refuses unmanaged nonempty roots, path escapes, malformed identities, corrupt profiles, and partial collisions. This local workflow does not claim Archive Recall's canonical preservation ownership.
| Drive-letter planning | Recognized Windows data partitions without letters | Positive/negative deterministic fixtures plus actual five-disk/eight-partition scan | A free letter can be recommended without mutation only for a recognized, non-system, non-hidden, non-raw data volume | Assignment is not implemented; actual scan found zero eligible volumes because all unlettered partitions are protected system partitions |

## Oldest-to-newest adapter strategy

Compatibility must be earned by transport and evidence lane rather than a single universal device claim:

- Analog sources such as VHS, Video8, cassette, and vinyl require a user-owned capture interface, signal monitoring, lossless or declared-codec capture, and frame/sample evidence. They are not block storage.
- Legacy block media such as floppy, removable cartridges, IDE/SCSI disks, early MP3 players, and USB mass storage can use read-only mounted-file and full-disk lanes when Windows exposes a stable device. Each controller and named hardware family still needs evidence.
- Optical media requires drive/media detection, bounded sector reads, image verification, and explicit handling of unreadable sectors. Copy-protection bypass is not included.
- Modern SATA/NVMe devices need identity pinning, SMART/health observation, partition awareness, and strict system/boot-disk exclusion before acquisition or cloning.
- Protocol devices such as MTP/PTP cameras, Android devices, and trusted iPhones need dedicated adapters. A missing drive letter is not automatically a fault.
- Cloud libraries and vendor backups require authenticated export adapters, provenance, encryption-state preservation, and receipts; they must not be represented as raw disks.

## Apple-device boundary

Current Apple guidance uses the Apple Devices app on Windows for trusted-device backup, restore, file transfer, and synchronization. Music synchronization also depends on the Apple Music app and account/library state. A future Legacy Doctor Apple adapter must therefore consume explicit Apple-produced backup or transfer surfaces and preserve encryption/trust state; it must not treat a modern iPhone as an ordinary mounted disk.

Authoritative references:

- <https://support.apple.com/guide/devices-windows/back-up-and-restore-your-device-mchla3c8ed03/windows>
- <https://support.apple.com/guide/devices-windows/sync-your-content-between-devices-mchlde9a31f1/windows>
- <https://support.apple.com/en-us/108353>

## Proof policy

Hardware compatibility requires a receipt from named hardware plus independent destination-hash verification. Synthetic fixtures prove deterministic algorithms and classification boundaries only. Protected content, credential bypass, DRM circumvention, and destructive source modification are outside this proposal.
