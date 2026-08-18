# Proposal: Legacy media compatibility and proof matrix v1

Status: proposed; mounted-media catalog and bounded backup lanes implemented

## Product goal

Legacy Doctor should preserve accessible user-owned content from legacy storage and device ecosystems while producing receipts that distinguish observed evidence from inferred format hints. A green test may claim only the lane it actually exercises.

## Current conflict requiring canonical review

`docs/SPECIFICATION.md` and `docs/ROADMAP.md` describe deterministic formatting as a product purpose. The supported Storage-03 implementation and the proposed service identity instead quarantine formatting and define a non-destructive recovery boundary. This proposal does not resolve that canonical/product-definition conflict; it requires operator and ecosystem review.

## Compatibility lanes

| Lane | Intended sources | Current proof level | Allowed claim | Explicit non-claim |
|---|---|---|---|---|
| Mounted-media catalog | Any readable mounted directory | Deterministic fixture and copy/hash proof | Files can be enumerated, classified by path/extension hints, hashed, and reproduced byte-for-byte by the fixture harness | No claim that arbitrary hardware mounts or that every file is semantically valid |
| Legacy iPod disk layout | Readable `iPod_Control` trees | Synthetic layout fixture | The catalog recognizes files located under an `iPod_Control` tree | No physical iPod, iTunesDB parsing, playlist reconstruction, or device write support yet |
| iPhone, iPad, iPod touch | Apple Devices app / trusted Apple-device connection | Not implemented | Future adapter boundary only | No pairing bypass, protected-data extraction, sync, restore, or direct device backup claim |
| DVD-Video files | Readable mounted `VIDEO_TS` trees | Synthetic layout fixture | `.IFO`, `.BUP`, and `.VOB` files under `VIDEO_TS` are preserved as DVD-Video candidates | No optical-drive hardware proof, playback validation, CSS/decryption, or copy-protection bypass |
| Optical images | User-accessible `.iso`, `.img`, `.nrg`, `.mdf` files | Synthetic file fixture | Files are preserved as opaque optical-image candidates | No filesystem mounting or image-content validation |
| ROM collections | User-accessible ROM-like files | Synthetic extension fixture | Files can be preserved and labeled as ROM candidates using bounded extension/path hints | No emulator, provenance, ownership, or playability claim |
| `.cos` artifacts | User-accessible `.cos` files | Synthetic extension fixture | Files can be preserved as opaque COS artifacts | No assumption about which COS format produced the file and no execution/parsing claim |
| Bounded mounted-file backup | Explicit readable source and existing destination directories | Deterministic execution fixture with destination SHA-256 verification | A bounded set of ordinary files can be copied without overwriting, with source/destination separation, temporary-file verification, and fail-closed receipts | Physical-device compatibility still requires named-hardware evidence; this is not raw imaging or a device-protocol adapter |

## Apple-device boundary

Current Apple guidance uses the Apple Devices app on Windows for trusted-device backup, restore, file transfer, and synchronization. Music synchronization also depends on the Apple Music app and account/library state. A future Legacy Doctor Apple adapter must therefore consume explicit Apple-produced backup or transfer surfaces and preserve encryption/trust state; it must not treat a modern iPhone as an ordinary mounted disk.

Authoritative references:

- <https://support.apple.com/guide/devices-windows/back-up-and-restore-your-device-mchla3c8ed03/windows>
- <https://support.apple.com/guide/devices-windows/sync-your-content-between-devices-mchlde9a31f1/windows>
- <https://support.apple.com/en-us/108353>

## Proof policy

Hardware compatibility requires a receipt from named hardware plus independent destination-hash verification. Synthetic fixtures prove deterministic algorithms and classification boundaries only. Protected content, credential bypass, DRM circumvention, and destructive source modification are outside this proposal.
