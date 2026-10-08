param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [Parameter(Mandatory=$true)][string]$DestinationRoot,
  [switch]$RecoverStalePartials,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function EnsureDir([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Container)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null } }
function Write-Lf([string]$Path,[string]$Text){
  EnsureDir (Split-Path -Parent $Path)
  $normalized = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $normalized.EndsWith("`n")){ $normalized += "`n" }
  [IO.File]::WriteAllText($Path,$normalized,[Text.UTF8Encoding]::new($false))
}
function Add-Unique([object[]]$Items,[string]$Value){ $r = @($Items); if(-not ($r -contains $Value)){ $r += $Value }; return @($r) }

# SHA-256 of the first $Length bytes of a file.
function Get-PrefixSha256([string]$Path,[Int64]$Length){
  $sha = [Security.Cryptography.SHA256]::Create()
  $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try {
    $buffer = New-Object byte[] 1048576
    [Int64]$remaining = $Length
    while($remaining -gt 0){
      $want = [int][Math]::Min([Int64]$buffer.Length,$remaining)
      $read = $stream.Read($buffer,0,$want)
      if($read -le 0){ throw "PREFIX_READ_SHORT" }
      [void]$sha.TransformBlock($buffer,0,$read,$null,0)
      $remaining -= $read
    }
    [void]$sha.TransformFinalBlock((New-Object byte[] 0),0,0)
    return (($sha.Hash | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $stream.Dispose()
    $sha.Dispose()
  }
}

if(-not ("LdBlockCompare" -as [type])){
  Add-Type -TypeDefinition @"
public static class LdBlockCompare {
  public static int FirstDiff(byte[] a, byte[] b, int count){
    for(int i = 0; i < count; i++){ if(a[i] != b[i]){ return i; } }
    return -1;
  }
  public static bool AllZero(byte[] a, int start, int count){
    for(int i = start; i < start + count; i++){ if(a[i] != 0){ return false; } }
    return true;
  }
}
"@
}

# A partial is consistent with an interrupted copy when it is an exact prefix of the source, or an exact prefix
# followed only by zero bytes (an allocated but unwritten tail, which a real killed copy leaves behind).
# Returns mismatch_at = -1 for an exact prefix, otherwise the number of leading bytes that match.
function Compare-PartialToSource([string]$PartialPath,[string]$SourcePath){
  $partialStream = [IO.File]::Open($PartialPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $sourceStream = [IO.File]::Open($SourcePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try {
    $partialBlock = New-Object byte[] 1048576
    $sourceBlock = New-Object byte[] 1048576
    [Int64]$offset = 0
    [Int64]$mismatchAt = -1
    $consistent = $true
    while($consistent){
      $partialRead = $partialStream.Read($partialBlock,0,$partialBlock.Length)
      if($partialRead -le 0){ break }
      $sourceRead = 0
      while($sourceRead -lt $partialRead){
        $n = $sourceStream.Read($sourceBlock,$sourceRead,$partialRead - $sourceRead)
        if($n -le 0){ break }
        $sourceRead += $n
      }
      if($mismatchAt -lt 0){
        $compareCount = [Math]::Min($partialRead,$sourceRead)
        $diff = [LdBlockCompare]::FirstDiff($partialBlock,$sourceBlock,$compareCount)
        if($diff -ge 0){
          $mismatchAt = $offset + $diff
          $consistent = [LdBlockCompare]::AllZero($partialBlock,$diff,$partialRead - $diff)
        } elseif($sourceRead -lt $partialRead){
          $mismatchAt = $offset + $sourceRead
          $consistent = [LdBlockCompare]::AllZero($partialBlock,$sourceRead,$partialRead - $sourceRead)
        }
      } else {
        $consistent = [LdBlockCompare]::AllZero($partialBlock,0,$partialRead)
      }
      $offset += $partialRead
    }
    return [pscustomobject]@{ consistent = [bool]$consistent; mismatch_at = [Int64]$mismatchAt }
  } finally {
    $partialStream.Dispose()
    $sourceStream.Dispose()
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_ld_receipts_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_destination_profile_v1.ps1")

$suffix = ".legacy-doctor.partial"
$blockers = @()
$rows = @()
$status = "no_partials"
$quarantinedCount = 0

$sourceFull = LDDST-FullPath $SourceRoot
$destinationFull = LDDST-FullPath $DestinationRoot
$selftestRoot = Join-Path $RepoRoot "proofs\selftest"
$quarantineRoot = Join-Path $destinationFull "quarantine\stale-partials"

if(-not (Test-Path -LiteralPath $sourceFull -PathType Container)){ $blockers = Add-Unique $blockers "SOURCE_ROOT_MISSING" }
if(-not (Test-Path -LiteralPath $destinationFull -PathType Container)){ $blockers = Add-Unique $blockers "DESTINATION_ROOT_MISSING" }
if((LDDST-IsSameOrNested $destinationFull $sourceFull) -or (LDDST-IsSameOrNested $sourceFull $destinationFull)){ $blockers = Add-Unique $blockers "SOURCE_DESTINATION_OVERLAP" }
if(((LDDST-IsSameOrNested $destinationFull $RepoRoot) -and -not (LDDST-IsSameOrNested $destinationFull $selftestRoot)) -or (LDDST-IsSameOrNested $RepoRoot $destinationFull)){ $blockers = Add-Unique $blockers "REPO_ROOT_DESTINATION_FORBIDDEN" }
if($Execute.IsPresent -and -not $RecoverStalePartials.IsPresent){ $blockers = Add-Unique $blockers "EXECUTE_REQUIRES_RECOVER_FLAG" }

$partials = @()
if(@($blockers).Count -eq 0){
  try {
    $partials = @(Get-ChildItem -LiteralPath $destinationFull -File -Recurse -Force -Filter ("*" + $suffix) -ErrorAction Stop |
      Where-Object { -not (LDDST-IsSameOrNested $_.FullName $quarantineRoot) } |
      Sort-Object FullName)
  } catch {
    $blockers = Add-Unique $blockers "DESTINATION_ENUMERATION_FAILED"
  }
}

foreach($partial in $partials){
  $relativeWithSuffix = $partial.FullName.Substring($destinationFull.TrimEnd("\").Length + 1)
  $relative = $relativeWithSuffix.Substring(0,$relativeWithSuffix.Length - $suffix.Length)
  $finalPath = Join-Path $destinationFull $relative
  $sourcePath = Join-Path $sourceFull $relative
  $partialBytes = [Int64]$partial.Length
  $sourceBytes = [Int64]0
  $partialSha = ""
  $copiedPrefix = [Int64]0
  $classification = "blocked"
  $reason = ""

  if(Test-Path -LiteralPath $finalPath -PathType Leaf){
    $reason = "FINAL_FILE_PRESENT"
  } elseif(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)){
    $reason = "SOURCE_FILE_MISSING"
  } else {
    $sourceBytes = [Int64](Get-Item -LiteralPath $sourcePath -Force).Length
    if($partialBytes -gt $sourceBytes){
      $reason = "PARTIAL_LARGER_THAN_SOURCE"
    } else {
      try {
        $partialSha = Get-PrefixSha256 $partial.FullName $partialBytes
        $comparison = Compare-PartialToSource $partial.FullName $sourcePath
        if($comparison.consistent){
          $classification = "recoverable"
          if($comparison.mismatch_at -lt 0){ $reason = "EXACT_PREFIX_OF_SOURCE"; $copiedPrefix = $partialBytes }
          else { $reason = "PREFIX_WITH_ZERO_FILLED_TAIL"; $copiedPrefix = [Int64]$comparison.mismatch_at }
        } else { $reason = "PARTIAL_NOT_SOURCE_PREFIX" }
      } catch {
        $reason = "PARTIAL_OR_SOURCE_UNREADABLE"
      }
    }
  }

  $rows += [ordered]@{
    relative_path = $relative
    classification = $classification
    reason = $reason
    partial_bytes = $partialBytes
    copied_prefix_bytes = $copiedPrefix
    source_bytes = $sourceBytes
    partial_sha256 = $partialSha
    quarantine_path = ""
    quarantined = $false
    post_move_sha256 = ""
  }
}

$recoverableCount = @($rows | Where-Object { $_.classification -eq "recoverable" }).Count
$blockedCount = @($rows | Where-Object { $_.classification -eq "blocked" }).Count
if($blockedCount -gt 0){ $blockers = Add-Unique $blockers "UNRECOVERABLE_PARTIAL_PRESENT" }

if(@($blockers).Count -eq 0 -and $rows.Count -gt 0){
  $status = "plan_ready"
  if($Execute.IsPresent -and $RecoverStalePartials.IsPresent){
    $runId = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
    $runQuarantine = Join-Path $quarantineRoot $runId
    $collision = $false
    foreach($row in $rows){
      if(Test-Path -LiteralPath (Join-Path $runQuarantine ($row.relative_path + $suffix))){ $collision = $true }
    }
    if($collision){
      $blockers = Add-Unique $blockers "QUARANTINE_COLLISION"
    } else {
      $moved = @()
      try {
        foreach($row in $rows){
          $from = Join-Path $destinationFull ($row.relative_path + $suffix)
          $to = Join-Path $runQuarantine ($row.relative_path + $suffix)
          EnsureDir (Split-Path -Parent $to)
          [IO.File]::Move($from,$to)
          $moved += [ordered]@{ from = $from; to = $to }
          $after = Get-PrefixSha256 $to ([Int64]$row.partial_bytes)
          if($after -cne [string]$row.partial_sha256){ throw "QUARANTINE_HASH_MISMATCH" }
          if(Test-Path -LiteralPath $from){ throw "PARTIAL_STILL_AT_ORIGIN" }
          $row.quarantine_path = $to
          $row.quarantined = $true
          $row.post_move_sha256 = $after
        }
        $status = "quarantined"
        $quarantinedCount = @($rows | Where-Object { $_.quarantined }).Count
      } catch {
        $blockers = Add-Unique $blockers ("QUARANTINE_FAILED:" + [string]$_.Exception.Message)
        foreach($entry in @($moved | Sort-Object { $_.to } -Descending)){
          try { if(Test-Path -LiteralPath $entry.to){ [IO.File]::Move($entry.to,$entry.from) } } catch { $blockers = Add-Unique $blockers "ROLLBACK_FAILED" }
        }
        foreach($row in $rows){ $row.quarantine_path = ""; $row.quarantined = $false; $row.post_move_sha256 = "" }
      }
    }
  }
}

$ok = (@($blockers).Count -eq 0)
if(-not $ok){ $status = "blocked" }
$availability = "available"
if(-not $ok){ $availability = "blocked" }

$receipt = [ordered]@{
  schema = "ld.device.storage03_interruption_recovery.receipt.v1"
  event_type = "ld.device.storage03_interruption_recovery.receipt.v1"
  ok = [bool]$ok
  availability = $availability
  repo_root = $RepoRoot
  mode = "storage03_interruption_recovery"
  destructive = $false
  writes_source = $false
  execute_requested = [bool]$Execute.IsPresent
  recover_requested = [bool]$RecoverStalePartials.IsPresent
  source_root = $sourceFull
  destination_root = $destinationFull
  partial_count = [int]$rows.Count
  recoverable_count = [int]$recoverableCount
  blocked_count = [int]$blockedCount
  quarantined_count = [int]$quarantinedCount
  status = $status
  quarantine_root = $quarantineRoot
  rows = @($rows)
  blockers = @($blockers)
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_storage03_interruption_recovery"
EnsureDir $outDir
$outPath = Join-Path $outDir ("storage03_interruption_recovery_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")
$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Lf $outPath $json
Write-Output ("DEVICE_STORAGE03_INTERRUPTION_RECOVERY_PATH: " + $outPath)
Write-Output $json
if($ok){ Write-Output "LD_DEVICE_STORAGE03_INTERRUPTION_RECOVERY_OK" } else { Write-Output "LD_DEVICE_STORAGE03_INTERRUPTION_RECOVERY_BLOCKED" }
