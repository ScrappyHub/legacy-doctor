param(
  [Parameter(Mandatory=$true)][string]$Root,

  # Producer identity
  [Parameter(Mandatory=$true)][string]$Producer,              # e.g. "legacy_doctor"
  [Parameter(Mandatory=$true)][string]$ProducerInstance,      # e.g. $env:COMPUTERNAME or stable app instance id

  # Event
  [Parameter(Mandatory=$true)][string]$EventType,             # e.g. "legacy_doctor.health.snapshot.v1"
  [Parameter(Mandatory=$false)][string[]]$PrevLinks = @(),    # array of prior commit hashes this depends on
  [Parameter(Mandatory=$true)][ValidateSet("evidence","deterministic")][string]$Strength,

  # Content reference (pointer-only is allowed; "sealed" is allowed)
  [Parameter(Mandatory=$true)][string]$ContentRef,            # e.g. "sealed" OR "sha256:<hash>" OR "local:artifact/<id>"

  # Signing + principals
  [Parameter(Mandatory=$true)][string]$Principal,             # "<tenant>/<role>/<subject>"
  [Parameter(Mandatory=$true)][string]$ProducerKeyId,         # stable id for key (you choose; often pubkey sha256)
  [Parameter(Mandatory=$true)][string]$SshPrivateKeyPath,     # path to private key used by ssh-keygen -Y sign
  [Parameter(Mandatory=$false)][string]$SshNamespace = "nfl",  # ssh-keygen -Y sign namespace

  # Local pledge log location
  [Parameter(Mandatory=$false)][string]$LocalPledgeDir = "",  # default: "$Root\.nfl\pledges\"

  # NFL outbox location (Packet Constitution v1 transport)
  [Parameter(Mandatory=$true)][string]$NflOutbox              # e.g. "C:\ProgramData\NFL\inbox\" or outbox (your choice)
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"


function EnsureSshKeyPair([string]$PrivKeyPath){
  $pub = ($PrivKeyPath + ".pub")
  $dir = Split-Path -Parent $PrivKeyPath
  if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }

  if(-not (Test-Path -LiteralPath $PrivKeyPath)){
    Write-Host ("KEYGEN: creating ed25519 key: {0}" -f $PrivKeyPath) -ForegroundColor Yellow
    & ssh-keygen -t ed25519 -N "" -f $PrivKeyPath | Out-Null
  }
  if(-not (Test-Path -LiteralPath $PrivKeyPath)){ throw "KEYGEN_FAILED: missing private key: $PrivKeyPath" }
  if(-not (Test-Path -LiteralPath $pub)){ throw "KEYGEN_FAILED: missing public key: $pub" }
  return $PrivKeyPath
}
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }

function EnsureDir([string]$p){
  if(-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function WriteUtf8([string]$path, [string]$text){
  EnsureDir (Split-Path -Parent $path)
  $norm = $text.Replace("`r`n","`n").Replace("`r","`n").Replace("`n","`r`n")
  [System.IO.File]::WriteAllText($path, $norm, (Utf8NoBom))
  if(-not (Test-Path -LiteralPath $path)) { throw "WRITE_FAILED: $path" }
}

function ReadUtf8([string]$path){
  if(-not (Test-Path -LiteralPath $path)) { return "" }
  return (Get-Content -Raw -LiteralPath $path -Encoding UTF8)
}

function Sha256HexBytes([byte[]]$bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash($bytes)
    return ($h | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally { $sha.Dispose() }
}

function Sha256HexFile([string]$path){
  $bytes = [System.IO.File]::ReadAllBytes($path)
  return Sha256HexBytes $bytes
}

function ToIso8601Utc([datetime]$dt){
  return $dt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

function JsonEscape([string]$s){
  if($null -eq $s){ return "null" }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach($ch in $s.ToCharArray()){
    switch([int][char]$ch){
      34 { [void]$sb.Append('\"') }       # "
      92 { [void]$sb.Append('\\') }       # \
      8  { [void]$sb.Append('\b') }
      12 { [void]$sb.Append('\f') }
      10 { [void]$sb.Append('\n') }
      13 { [void]$sb.Append('\r') }
      9  { [void]$sb.Append('\t') }
      default {
        $code = [int][char]$ch
        if($code -lt 32){
          [void]$sb.Append('\u' + $code.ToString("x4"))
        } else {
          [void]$sb.Append($ch)
        }
      }
    }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}

function JsonArrayOfStrings([string[]]$arr){
  if($null -eq $arr -or $arr.Count -eq 0){ return "[]" }
  $items = @()
  foreach($x in $arr){ $items += (JsonEscape $x) }
  return "[" + ($items -join ",") + "]"
}

# Canonical commitment payload bytes (fixed field order; no interpretation drift)
function BuildCommitPayloadJson(
  [string]$Producer,
  [string]$ProducerInstance,
  [string]$EventType,
  [string]$EventTimeIso,
  [string[]]$PrevLinks,
  [string]$ContentRef,
  [string]$Strength
){
  # policy_tags + notes_ref intentionally omitted here (optional)
  # You can extend later, but DO NOT reorder existing fields once locked.
  $j =
    "{"+
    '"schema":"commitment.v1",'+
    '"producer":'+(JsonEscape $Producer)+','+
    '"producer_instance":'+(JsonEscape $ProducerInstance)+','+
    '"event_type":'+(JsonEscape $EventType)+','+
    '"event_time":'+(JsonEscape $EventTimeIso)+','+
    '"prev_links":'+(JsonArrayOfStrings $PrevLinks)+','+
    '"content_ref":'+(JsonEscape $ContentRef)+','+
    '"strength":'+(JsonEscape $Strength)+
    "}"
  return $j
}

function RequireExe([string]$name){
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if(-not $cmd){ throw "MISSING_EXE: $name (required for signatures)" }
  return $cmd.Path
}

function SshSignDetached([string]$PrivKey,[string]$Namespace,[string]$Principal,[string]$MessageFile,[string]$OutSig){
  $ssh = RequireExe "ssh-keygen"
  EnsureDir (Split-Path -Parent $OutSig)

  # ssh-keygen -Y sign writes "<file>.sig" by default when -f/-n/-I given
  # We'll sign the bytes in $MessageFile, then move to deterministic path.
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nfl_msg_" + [Guid]::NewGuid().ToString("n") + ".bin")
  Copy-Item -LiteralPath $MessageFile -Destination $tmp -Force

  # Important: use -I identity (we set to Principal) and -n namespace
  & $ssh -Y sign -f $PrivKey -n $Namespace -I $Principal $tmp | Out-Null

  $genSig = $tmp + ".sig"
  if(-not (Test-Path -LiteralPath $genSig)) { throw "SIGN_FAILED: ssh-keygen did not emit .sig" }

  Move-Item -LiteralPath $genSig -Destination $OutSig -Force
  Remove-Item -LiteralPath $tmp -Force
  if(-not (Test-Path -LiteralPath $OutSig)) { throw "SIGN_WRITE_FAILED: $OutSig" }
}

function WriteSha256Sums([string]$RootDir, [string[]]$RelFiles, [string]$OutPath){
  $lines = @()
  foreach($rel in $RelFiles){
    $abs = Join-Path $RootDir $rel
    if(-not (Test-Path -LiteralPath $abs)) { throw "SHA256_MISSING_FILE: $abs" }
    $h = Sha256HexFile $abs
    # sha256sum format: "<hash>  <path>"
    $lines += ("{0}  {1}" -f $h, $rel.Replace("\","/"))
  }
  WriteUtf8 $OutPath (($lines -join "`n") + "`n")
}

function ParseSha256Sums([string]$path){
  $raw = (Get-Content -Raw -LiteralPath $path -Encoding UTF8)
  $norm = $raw.Replace("`r`n","`n").Replace("`r","`n")
  $lines = $norm.Split("`n") | Where-Object { $_.Trim().Length -gt 0 }
  $map = @{}
  foreach($ln in $lines){
    # "<hash>  <file>"
    $parts = $ln -split "\s\s+"
    if($parts.Count -lt 2){ throw "BAD_SHA256SUMS_LINE: $ln" }
    $map[$parts[1].Trim()] = $parts[0].Trim().ToLowerInvariant()
  }
  return $map
}

function Sha256SumsDigest([string]$shaFile){
  $bytes = [System.IO.File]::ReadAllBytes($shaFile)
  return Sha256HexBytes $bytes
}

# ----------------------------
# Defaults & paths
# ----------------------------
if([string]::IsNullOrWhiteSpace($LocalPledgeDir)){
  $LocalPledgeDir = Join-Path $Root ".nfl\pledges"
}
EnsureDir $LocalPledgeDir
EnsureDir $NflOutbox

$commitDir = Join-Path $LocalPledgeDir "commits"
EnsureDir $commitDir

$pledgeLog = Join-Path $LocalPledgeDir "pledge_log.ndjson"

# ----------------------------
# 1) Commit(event_type, prev_links, payload_bytes_or_ref, strength) -> CommitHash
# ----------------------------
$eventTime = ToIso8601Utc (Get-Date)
$payloadJson = BuildCommitPayloadJson `
  -Producer $Producer `
  -ProducerInstance $ProducerInstance `
  -EventType $EventType `
  -EventTimeIso $eventTime `
  -PrevLinks $PrevLinks `
  -ContentRef $ContentRef `
  -Strength $Strength

$payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payloadJson)
$commitHash = Sha256HexBytes $payloadBytes

$payloadPath = Join-Path $commitDir ("commit.payload.{0}.json" -f $commitHash)
WriteUtf8 $payloadPath ($payloadJson + "`n")

# Create a minimal message file for signing: CommitHash + newline + Principal + newline (context)
$msg = "{0}`n{1}`n" -f $commitHash, $Principal
$msgPath = Join-Path $commitDir ("commit.msg.{0}.txt" -f $commitHash)
WriteUtf8 $msgPath $msg

$payloadSigPath = Join-Path $commitDir ("commit.payload.{0}.sig" -f $commitHash)
$SshPrivateKeyPath = EnsureSshKeyPair $SshPrivateKeyPath

SshSignDetached -PrivKey $SshPrivateKeyPath -Namespace $SshNamespace -Principal $Principal -MessageFile $msgPath -OutSig $payloadSigPath

# ----------------------------
# 2) PledgeLocal(CommitHash, payload, producer_sig) -> append chained log
# ----------------------------
$prevLogHash = "0"*64
$seq = 1
if(Test-Path -LiteralPath $pledgeLog){
  $last = (Get-Content -LiteralPath $pledgeLog -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -Last 1)
  if($last){
    try {
      $o = $last | ConvertFrom-Json
      if($o.local_record_hash){ $prevLogHash = [string]$o.local_record_hash }
      if($o.local_sequence){ $seq = ([int]$o.local_sequence) + 1 }
    } catch {
      throw "PLEDGE_LOG_PARSE_FAILED: $pledgeLog"
    }
  }
}

# Build canonical local pledge record (fixed order; NDJSON line)
# Note: store pointers (payload path + sig path) not the whole payload again.
$rec =
  "{"+
  '"schema":"local.pledge.v1",'+
  '"commit_hash":'+(JsonEscape $commitHash)+','+
  '"producer":'+(JsonEscape $Producer)+','+
  '"producer_instance":'+(JsonEscape $ProducerInstance)+','+
  '"event_type":'+(JsonEscape $EventType)+','+
  '"producer_time":'+(JsonEscape $eventTime)+','+
  '"prev_links":'+(JsonArrayOfStrings $PrevLinks)+','+
  '"strength":'+(JsonEscape $Strength)+','+
  '"content_ref":'+(JsonEscape $ContentRef)+','+
  '"producer_principal":'+(JsonEscape $Principal)+','+
  '"producer_key_id":'+(JsonEscape $ProducerKeyId)+','+
  '"payload_path":'+(JsonEscape ($payloadPath.Substring($Root.Length).TrimStart("\") -replace "\\","/"))+','+
  '"sig_path":'+(JsonEscape ($payloadSigPath.Substring($Root.Length).TrimStart("\") -replace "\\","/"))+','+
  '"local_sequence":'+$seq+','+
  '"local_prev_log_hash":'+(JsonEscape $prevLogHash)+
  "}"

$recBytes = [System.Text.Encoding]::UTF8.GetBytes($rec)
$recHash = Sha256HexBytes $recBytes

$rec2 = $rec.TrimEnd("}") + ',"local_record_hash":' + (JsonEscape $recHash) + "}"

# Append as NDJSON (deterministic newline)
EnsureDir (Split-Path -Parent $pledgeLog)
Add-Content -LiteralPath $pledgeLog -Encoding UTF8 -Value $rec2

Write-Host ("COMMIT OK: {0}" -f $commitHash) -ForegroundColor Green
Write-Host ("PLEDGE OK: seq={0} record_hash={1}" -f $seq, $recHash) -ForegroundColor Green

# ----------------------------
# 3) DuplicateToNFL(CommitHash, payload_or_sealed, producer_sig) -> emit packet to NFL outbox
# ----------------------------
# Allowed/Permitted for Legacy Doctor (v1):
# - We include commit payload JSON + ingest envelope JSON + sha256sums + detached signature
# - We DO NOT include any sensitive “content blobs” by default. content_ref remains pointer-only or "sealed".
$packetStaging = Join-Path $LocalPledgeDir ("packet_staging_" + [Guid]::NewGuid().ToString("n"))
EnsureDir $packetStaging

$payloadDir = Join-Path $packetStaging "payload"
$signDir    = Join-Path $packetStaging "signatures"
EnsureDir $payloadDir
EnsureDir $signDir

# nfl ingest envelope
$ingestJson =
  "{"+
  '"schema":"nfl.ingest.v1",'+
  '"commit_hash":'+(JsonEscape $commitHash)+','+
  '"producer":'+(JsonEscape $Producer)+','+
  '"producer_sig":'+(JsonEscape ("sigfile:" + ("signatures/producer.sig")))+','+
  '"producer_key_id":'+(JsonEscape $ProducerKeyId)+','+
  '"producer_principal":'+(JsonEscape $Principal)+','+
  '"prev_links":'+(JsonArrayOfStrings $PrevLinks)+','+
  '"event_type":'+(JsonEscape $EventType)+','+
  '"producer_time":'+(JsonEscape $eventTime)+','+
  '"payload_bytes_mode":"plaintext_commit_payload_only"'+
  "}"

$ingestPath = Join-Path $payloadDir "ingest.json"
WriteUtf8 $ingestPath ($ingestJson + "`n")

# include commit payload itself (permitted minimal)
Copy-Item -LiteralPath $payloadPath -Destination (Join-Path $payloadDir "commit.payload.json") -Force

# sha256sums over included payload files (canonical)
$shaPath = Join-Path $packetStaging "sha256sums.txt"
$relFiles = @(
  "payload/ingest.json",
  "payload/commit.payload.json"
)
WriteSha256Sums -RootDir $packetStaging -RelFiles $relFiles -OutPath $shaPath

# sign message = CommitHash + sha256sums_digest (canonical for this packet)
$shaDigest = Sha256SumsDigest $shaPath
$msg2 = "{0}`n{1}`n" -f $commitHash, $shaDigest
$msg2Path = Join-Path $packetStaging "packet.msg.txt"
WriteUtf8 $msg2Path $msg2

$producerSigOut = Join-Path $signDir "producer.sig"
$SshPrivateKeyPath = EnsureSshKeyPair $SshPrivateKeyPath

SshSignDetached -PrivKey $SshPrivateKeyPath -Namespace $SshNamespace -Principal $Principal -MessageFile $msg2Path -OutSig $producerSigOut

# manifest.json (minimal)
$manifest =
  "{"+
  '"schema":"packet.manifest.v1",'+
  '"producer":'+(JsonEscape $Producer)+','+
  '"commit_hash":'+(JsonEscape $commitHash)+','+
  '"created_time":'+(JsonEscape (ToIso8601Utc (Get-Date)))+','+
  '"files":'+
    "["+
      (JsonEscape "payload/ingest.json")+","+
      (JsonEscape "payload/commit.payload.json")+","+
      (JsonEscape "sha256sums.txt")+","+
      (JsonEscape "signatures/producer.sig")+
    "]"+
  "}"

$manifestPath = Join-Path $packetStaging "manifest.json"
WriteUtf8 $manifestPath ($manifest + "`n")

# add manifest + signature file to sha256sums (canonical list extended)
$relFiles2 = @(
  "manifest.json",
  "payload/ingest.json",
  "payload/commit.payload.json",
  "sha256sums.txt",
  "signatures/producer.sig"
)
WriteSha256Sums -RootDir $packetStaging -RelFiles $relFiles2 -OutPath $shaPath

# packet identity = sha256(sha256sums bytes) (content-address packet folder name)
$packetId = Sha256HexFile $shaPath

$packetFinal = Join-Path $NflOutbox $packetId
if(Test-Path -LiteralPath $packetFinal){
  # idempotent: if it already exists, do not overwrite; just report
  Write-Host ("NFL OUTBOX already has packet: {0}" -f $packetFinal) -ForegroundColor Yellow
} else {
  Move-Item -LiteralPath $packetStaging -Destination $packetFinal -Force
  Write-Host ("NFL OUTBOX EMIT OK: {0}" -f $packetFinal) -ForegroundColor Cyan
}

# leave commitHash on stdout for easy piping
$commitHash