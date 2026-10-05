# Security policy

Legacy Doctor handles storage devices and potentially irreplaceable data. Treat any unexpected device write, source mutation, target-selection error, path escape, false success receipt, or quarantine bypass as a security and data-safety vulnerability.

## Supported scope

Only the Storage-03 lanes described in the README are supported: read-only observation and planning lanes, the destination write probe, and the explicitly requested, bounded, hash-verified copy between non-overlapping mounted directories. The historical FAT32 formatter is quarantined and must not be enabled without an approved destructive-media contract and hardware safety review.

## Reporting

Do not include private user data, raw disk images, credentials, serial numbers, or full receipts containing machine paths in a public report. Report the affected commit, script, safe reproduction steps, observed receipt fields, and expected fail-closed behavior to the repository maintainers through a private GitHub security advisory when available.

## Safety rule

Do not reproduce suspected destructive behavior on media containing valuable data. Use disposable image files or dedicated sacrificial test devices only.
