# Legacy Doctor

---

Instrument-grade snapshot • archive • restore engine for governed systems

Legacy Doctor is a deterministic, cryptographically-verifiable backup and restore instrument.

It produces content-addressed, sealed, attestable artifacts that can be:

snapshotted

compressed

encrypted

transported offline

restored byte-for-byte

independently verified

witnessed by Never Forgetting Ledger (NFL)

Legacy Doctor is not a cloud backup tool and not a sync client.

It is an instrument — like a scientific device — designed to create provable system captures.

Purpose

Provide a Macrium-grade / 7zip-grade restore capability that is:

deterministic

hash-sealed

policy governed

air-gap friendly

independently attestable

Every restore can be proven correct, not merely trusted.

Core responsibilities

Legacy Doctor:

✅ snapshots file trees / partitions
✅ builds canonical archives
✅ compresses deterministically
✅ encrypts bundles (AES-GCM)
✅ emits sha256 manifests
✅ signs artifacts (ssh-ed25519)
✅ restores byte-exact
✅ verifies before commit
✅ pledges every operation locally
✅ duplicates every pledge to NFL

Legacy Doctor:

❌ does not manage devices (Watchtower does)
❌ does not enforce policy (Covenant Gate does)
❌ does not act as a ledger (NFL does)

Architecture
capture → archive → seal → sign → pledge → duplicate to NFL → restore → verify → commit

Artifact invariants

Every artifact is:

content-addressed

sha256 sealed

detached-signed

canonical JSON

UTF-8 no BOM + LF

Packet Constitution v1 compliant

Restore philosophy

Restores use dual verification:

byte hash integrity (sha256)

semantic integrity (tree + transcript + attestation)

No silent divergence.

Platform order (locked)

v1: Windows
v2: Linux
v3: macOS

Same schema. Same artifact layout. Only capture adapters differ.

Integration laws

Legacy Doctor follows:

Packet Constitution v1 (transport physics)

NeverLost identity layer

Local pledge log (append-only)

Mandatory duplication to NFL

It never communicates directly with other projects.

Only:

hashes → NFL
