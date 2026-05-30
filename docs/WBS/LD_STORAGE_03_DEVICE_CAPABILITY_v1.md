# LD-STORAGE-03 Device Capability Lane v1

Status: first checkpoint.

This lane is non-destructive.

Current scope:
- device inventory
- partitions
- volumes
- drive-letter mounted state
- no-drive-letter / no-partition recognition where Windows exposes enough metadata
- mount classification receipt
- backup relevance recommendation

This does not yet prove:
- benchmarking
- real raw imaging across all device classes
- snapshot acquisition
- complete SMART/vendor health
- full formatting coverage
- canonical storage library completeness

Next checkpoints:
- health probe v1
- read benchmark v1
- backup readiness v1
- real hardware walkthrough matrix
