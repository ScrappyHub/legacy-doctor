# Proposal: Storage-03R2 automatic interruption recovery v1

Status: design only; no code. Implementation is deliberately held until the current verifier run is green on Windows, because this lane touches destination bytes after a crash.

## Problem

03R proves restart from a durable promoted prefix. A stale `<name>.legacy-doctor.partial` still blocks the run, and an operator must clear it by hand. The roadmap's first item is to recover from that automatically without ever guessing.

## Contract

1. **Intent journal.** Before the first byte of each file is written, the executor appends one line to `<workspace>/metadata/copy_intent.ndjson` (canonical JSON, LF, UTF-8 without BOM): relative path, expected source SHA-256, expected size, partial path, run id. After promotion it appends a matching `promoted` line with the verified destination SHA-256. The journal is append-only evidence and is never rewritten.
2. **Stale-partial classification.** A partial is *recoverable* only if a journal intent exists for exactly that path, no `promoted` line follows it, the final file does not exist, and the source file still matches the intent hash and size. Anything else (no intent, source changed, final file present, size above intent) is *foreign or ambiguous* and keeps blocking.
3. **Governed quarantine, never deletion.** Recovery moves a recoverable partial to `<destination>/quarantine/stale-partials/<run id>/<relative path>.partial` using a rename, records its SHA-256 before and after the move, and then copies the file again from the source. A partial is never reused as a prefix and never deleted.
4. **Explicit authority.** Recovery runs only with `-RecoverStalePartials` together with `-Execute`. Without the flag the lane reports `partial_blocked` as it does today. A dry run lists what recovery would do and changes nothing.
5. **Bounds.** At most the existing manifest bounds. Recovery never touches paths outside the workspace payload and quarantine folders, and refuses a destination that overlaps the source or the repository.
6. **Receipt.** A new closed receipt `ld.device.storage03_interruption_recovery.receipt.v1` records per file: classification, reason code, quarantine path, hashes, and outcome. Unavailable or unreadable state blocks; it is never read as "no partials".

## Required proof (DoD gates)

Positive: interrupted copy with a valid intent recovers to byte-identical output and the original partial is preserved in quarantine. Negative, each must block and change nothing: partial without intent, intent with changed source, partial plus final file present, truncated or tampered journal, partial larger than the intent size, quarantine path collision, destination overlapping source, `-RecoverStalePartials` without `-Execute`. Replay: recovering twice is a no-op. Real interruption: kill the executor process mid-file (not a synthetic leftover) and recover.

## Does not prove

Power-loss or filesystem-level durability beyond what the destination reports, recovery on network shares or removable media (needs named-device evidence under 03T), or recovery of a source that changed during the run.

## Compatibility impact

Adds an optional journal and a new receipt. Existing 03P/03R receipts and schemas are unchanged, and the default behavior (block on any stale partial) stays the same.
