# Legacy Doctor â€” Artifact Format v1

## Layout
artifact_root/
  manifest.json
  sha256sums.txt
  transcript.ndjson
  payload/...
  signatures/ (optional)
  encryption/ (optional)

Text files are UTF-8 (no BOM) with LF newlines.

## sha256sums.txt
Each line:
  <SHA256_HEX><two spaces><relative_path>
relative_path uses forward slashes.

## manifest.json (minimum fields)
Includes:
- artifact_format id
- created_utc
- tool name/version/platform
- policy id/hash
- source identity
- payload description (files or chunks)
- optional chunking + merkle_root section

## transcript.ndjson
Append-only newline-delimited JSON events:
- ts_utc
- event
- level
- data