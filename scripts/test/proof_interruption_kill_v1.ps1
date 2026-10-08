param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$FileMegabytes = 300,
  [int]$MaxAttempts = 3
)

# Real-interruption proof for Storage-03R2. Not part of the unified verifier because it is timing-dependent and writes a large fixture.
# It starts the real executor, force-kills the process while a .legacy-doctor.partial exists, then proves
# block -> recover (quarantine) -> normal copy -> replay on the leftover state.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
function Require([bool]$Condition,[string]$Code,[string]$Detail){ if(-not $Condition){ Die $Code $Detail } }
function EnsureDir([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Container)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")

$base = Join-Path $RepoRoot "proofs\selftest\storage03_interruption_kill"
$allowed = [IO.Path]::GetFullPath((Join-Path $RepoRoot "proofs\selftest")).TrimEnd("\") + "\"
$full = [IO.Path]::GetFullPath($base)
Require ($full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) "FIXTURE_ESCAPE" $full
if(Test-Path -LiteralPath $full){ Remove-Item -LiteralPath $full -Recurse -Force }

$source = Join-Path $full "source"
EnsureDir $source
$bigPath = Join-Path $source "big\payload.bin"
EnsureDir (Split-Path -Parent $bigPath)
$chunk = New-Object byte[] 1048576
for($i = 0; $i -lt $chunk.Length; $i++){ $chunk[$i] = [byte](($i * 31 + 7) % 251) }
$stream = [IO.File]::Open($bigPath,[IO.FileMode]::Create,[IO.FileAccess]::Write)
try { for($m = 0; $m -lt $FileMegabytes; $m++){ $chunk[0] = [byte]($m % 256); $stream.Write($chunk,0,$chunk.Length) } } finally { $stream.Dispose() }
[IO.File]::WriteAllBytes((Join-Path $source "small.txt"),[Text.Encoding]::UTF8.GetBytes("small-file"))
$sourceHashes = @{}
foreach($file in @(Get-ChildItem -LiteralPath $source -File -Recurse)){ $sourceHashes[$file.FullName] = LDREC-HexSha256File $file.FullName }

$suffix = ".legacy-doctor.partial"
$backup = Join-Path $RepoRoot "scripts\media\ld_mounted_media_backup_v1.ps1"
$recovery = Join-Path $RepoRoot "scripts\storage\ld_storage03_interruption_recovery_v1.ps1"
$maxBytes = [string](([Int64]$FileMegabytes + 16) * 1048576)

$dest = ""
$partialPath = ""
$killed = $false
for($attempt = 1; $attempt -le $MaxAttempts -and -not $killed; $attempt++){
  $dest = Join-Path $full ("destination-attempt-" + $attempt)
  EnsureDir $dest
  $partialPath = Join-Path $dest ("big\payload.bin" + $suffix)
  $stdout = Join-Path $full ("executor-" + $attempt + ".stdout.txt")
  $stderr = Join-Path $full ("executor-" + $attempt + ".stderr.txt")
  $argList = @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",('"' + $backup + '"'),"-RepoRoot",('"' + $RepoRoot + '"'),"-SourceRoot",('"' + $source + '"'),"-DestinationRoot",('"' + $dest + '"'),"-MaxFiles","10","-MaxBytes",$maxBytes,"-Execute")
  $process = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $deadline = [DateTime]::UtcNow.AddSeconds(120)
  $caught = $false
  while([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited){
    if(Test-Path -LiteralPath $partialPath -PathType Leaf){
      $length = (Get-Item -LiteralPath $partialPath -Force).Length
      if($length -gt 0){
        Stop-Process -Id $process.Id -Force
        $caught = $true
        break
      }
    }
    Start-Sleep -Milliseconds 5
  }
  [void]$process.WaitForExit(30000)
  if($caught -and (Test-Path -LiteralPath $partialPath -PathType Leaf) -and -not (Test-Path -LiteralPath (Join-Path $dest "big\payload.bin"))){
    $killed = $true
    Write-Output ("KILLED_MID_COPY: attempt=" + $attempt + " partial_bytes=" + (Get-Item -LiteralPath $partialPath -Force).Length + " source_bytes=" + (Get-Item -LiteralPath $bigPath).Length)
  } else {
    Write-Output ("ATTEMPT_MISSED_WINDOW: attempt=" + $attempt)
  }
}
Require $killed "INCONCLUSIVE_COULD_NOT_KILL_MID_COPY" ("attempts=" + $MaxAttempts + "; rerun with a larger -FileMegabytes")

function Run-Recovery([bool]$ExecuteNow){
  $extra = @("-SourceRoot",$source,"-DestinationRoot",$dest,"-RecoverStalePartials")
  if($ExecuteNow){ $extra += "-Execute" }
  return (LDREC-RunReceiptScript -ScriptPath $recovery -RepoRoot $RepoRoot -ExpectedSchema "ld.device.storage03_interruption_recovery.receipt.v1" -ExtraArgs $extra)
}
function Run-Backup(){
  return (LDREC-RunReceiptScript -ScriptPath $backup -RepoRoot $RepoRoot -ExpectedSchema "ld.media.mounted_backup.receipt.v1" -ExtraArgs @("-SourceRoot",$source,"-DestinationRoot",$dest,"-MaxFiles","10","-MaxBytes",$maxBytes,"-Execute"))
}

# 1. The normal executor must refuse to continue over the leftover partial.
$blocked = Run-Backup
Require (-not [bool]$blocked.ok) "EXECUTOR_DID_NOT_BLOCK_ON_PARTIAL" ""
Require (@($blocked.blockers) -contains "STALE_PARTIAL_COLLISION") "EXECUTOR_BLOCK_REASON_MISSING" (@($blocked.blockers) -join ",")

# 2. Recovery plan classifies the real partial. A blocked classification here is a real finding, not a test bug.
$plan = Run-Recovery $false
$row = @($plan.rows | Where-Object { ([string]$_.relative_path) -eq "big\payload.bin" })[0]
Require ($null -ne $row) "PLAN_MISSING_ROW" ""
Require (([string]$row.classification) -eq "recoverable") "REAL_PARTIAL_NOT_RECOVERABLE" ([string]$row.reason + " partial_bytes=" + [string]$row.partial_bytes + " source_bytes=" + [string]$row.source_bytes)

# 3. Recover (quarantine), then the normal executor completes a byte-identical copy.
$recovered = Run-Recovery $true
Require ([bool]$recovered.ok) "RECOVERY_NOT_OK" (@($recovered.blockers) -join ",")
Require ([int]$recovered.quarantined_count -eq 1) "RECOVERY_COUNT_BAD" ([string]$recovered.quarantined_count)
Require (-not (Test-Path -LiteralPath $partialPath)) "PARTIAL_LEFT_AT_ORIGIN" $partialPath
$copy = Run-Backup
Require ([bool]$copy.ok) "POST_RECOVERY_COPY_NOT_OK" (@($copy.blockers) -join ",")
foreach($file in @(Get-ChildItem -LiteralPath $source -File -Recurse)){
  $relative = $file.FullName.Substring($source.Length + 1)
  Require ((LDREC-HexSha256File (Join-Path $dest $relative)) -ceq $sourceHashes[$file.FullName]) "POST_RECOVERY_BYTES_DIFFER" $relative
}

# 4. Replay is a no-op and the source never changed.
$replay = Run-Recovery $true
Require ([bool]$replay.ok -and ([string]$replay.status) -eq "no_partials") "REPLAY_NOT_NOOP" ([string]$replay.status)
foreach($path in @($sourceHashes.Keys)){ Require ((LDREC-HexSha256File $path) -ceq [string]$sourceHashes[$path]) "SOURCE_CHANGED" $path }

Write-Output "PASS: executor process killed mid-copy left a real partial that the executor then refused to continue over"
Write-Output "PASS: recovery classified the real partial as an exact prefix of the source and quarantined it with matching bytes"
Write-Output "PASS: normal executor then produced a byte-identical copy and recovery replay was a no-op"
Write-Output "LD_STORAGE03_INTERRUPTION_KILL_PROOF_OK"
