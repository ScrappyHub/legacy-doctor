# LD-STORAGE-03E Backup Readiness v1

Status: first checkpoint.

This lane is non-destructive.

It combines:
- inventory
- mount state
- health probe
- read probe

It emits operator recommendations:
- READY_FILE_BACKUP
- READY_RAW_IMAGE_NEEDS_ADMIN
- READY_RAW_IMAGE_ADMIN_PRESENT
- SKIP_SYSTEM_DISK_BY_DEFAULT
- NON_LETTERED_VOLUME_RAW_CANDIDATE
- RAW_PARTITION_CANDIDATE_NO_MOUNT
- NO_READABLE_VOLUME
- OFFLINE_NEEDS_OPERATOR_ACTION
- READABLE_BUT_HEALTH_REVIEW
- RAW_VOLUME_DETECTED_IMAGE_BEFORE_FORMAT

This does not perform backup, imaging, formatting, mounting, or writes.
It is a readiness and recommendation layer only.

Next checkpoints:
- file backup plan v1
- admin-gated raw image readiness v1
- hardware walkthrough matrix
