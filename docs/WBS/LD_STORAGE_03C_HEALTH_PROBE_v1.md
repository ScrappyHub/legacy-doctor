# LD-STORAGE-03C Health Probe v1

Status: first checkpoint.

This lane is non-destructive.

It records what Windows exposes:
- Get-Disk health and operational state
- Get-Volume health and operational state
- Get-PhysicalDisk metadata where available
- offline/read-only flags
- media type where available

It does not claim complete SMART coverage.
The receipt includes smart_claim = NOT_CLAIMED until a real SMART/vendor-specific lane is implemented.

Next checkpoints:
- read benchmark probe v1
- backup readiness v1
- hardware walkthrough matrix
