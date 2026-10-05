# Legacy Doctor Architecture v1

Legacy Doctor is a standalone storage-preservation instrument. The user experience may become a dashboard, but correctness belongs to the local contracts and proof runners.

```text
physical or protocol media
        ↓
discovery / identity / mount truth
        ↓
health + readability + capability classification
        ↓
preservation recommendation
        ↓
destination + privilege + operation gates
        ↓
file copy / raw image / optical image / extraction
        ↓
independent verification
        ↓
case packet and portable receipts
```

## Engines

1. Discovery and inspection.
2. Health and readability assessment.
3. Preservation decision.
4. File and block acquisition.
5. Independent verification.
6. Extraction and recovery.
7. Owned-media preparation behind destructive gates.
8. Evidence and case packaging.
9. Future repair/remediation lanes, never implicit.

Every engine has explicit inputs, versioned schemas, bounded writes, refusal states, and a proof runner. Missing hardware or protocol access becomes `unavailable`, `blocked`, or `manual_review`; it never becomes an inferred success.

## Ownership and integration

The current repository remains independently useful and does not require Archive Recall, TRIAD, NeverLost, WatchTower, or a cloud account. Optional integration will consume portable versioned artifacts only. The proposed future ecosystem layer is documented under `docs/proposals`; canonical ecosystem files remain unchanged until approved.
