# Legacy Doctor â€” Ops (Windows v1)

Principles:
- verify before restore
- transcript every run
- never claim success without cryptographic proof

Snapshot:
1) identify source + record identity
2) run snapshot -> emit manifest/sha256sums/transcript
3) verify artifact immediately

Restore:
1) verify artifact
2) identify target + record identity
3) stage -> verify -> activate (preferred)
4) emit restore transcript + restored proof