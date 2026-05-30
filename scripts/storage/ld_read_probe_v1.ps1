param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$MaxBytes = 262144,
  [int]$MaxFilesScanned = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function NormalizeDriveLetter([object]$Value){
  if($null -eq $Value){ return "" }
  $s = [string]$Value
  $s = $s.Replace([string][char]0,"").Trim()
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  return $s
}

function SafeStr([object]$Value){
  if($null -eq $Value){ return "" }
  return [string]$Value
}

function SafeU64([object]$Value){
  if($null -eq $Value){ return [UInt64]0 }
  return [UInt64]$Value
}

function HasProp([object]$Obj,[string]$Name){
  if($null -eq $Obj){ return $false }
  return (@($Obj.PSObject.Properties.Name) -contains $Name)
}

function GetProp([object]$Obj,[string]$Name){
  if(-not (HasProp $Obj $Name)){ return $null }
  return $Obj.PSObject.Properties[$Name].Value
}

function Find-SampleFile([string]$Root,[int]$MaxFilesScanned){
  if([string]::IsNullOrWhiteSpace($Root)){ return "" }
  if(-not (Test-Path -LiteralPath $Root -PathType Container)){ return "" }

  $scanned = 0

  try {
    foreach($f in [IO.Directory]::EnumerateFiles($Root)){
      $scanned++
      if($scanned -gt $MaxFilesScanned){ return "" }

      try {
        $fi = New-Object IO.FileInfo($f)
        if($fi.Exists -and $fi.Length -gt 0){ return $fi.FullName }
      } catch {
      }
    }
  } catch {
  }

  $dirs = @()
  try {
    foreach($d in [IO.Directory]::EnumerateDirectories($Root)){
      $dirs += $d
      if($dirs.Count -ge 20){ break }
    }
  } catch {
    $dirs = @()
  }

  foreach($d in @($dirs)){
    try {
      foreach($f in [IO.Directory]::EnumerateFiles($d)){
        $scanned++
        if($scanned -gt $MaxFilesScanned){ return "" }

        try {
          $fi = New-Object IO.FileInfo($f)
          if($fi.Exists -and $fi.Length -gt 0){ return $fi.FullName }
        } catch {
        }
      }
    } catch {
    }
  }

  return ""
}

function Read-Sample([string]$Path,[int]$MaxBytes){
  $result = [ordered]@{
    ok = $false
    bytes_read = [UInt64]0
    elapsed_ms = [UInt64]0
    mb_per_second_estimate = [double]0
    error = ""
  }

  if([string]::IsNullOrWhiteSpace($Path)){
    $result.error = "NO_SAMPLE_FILE"
    return $result
  }

  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    $result.error = "SAMPLE_FILE_MISSING"
    return $result
  }

  $buffer = New-Object byte[] 65536
  $total = [UInt64]0
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $fs = $null

  try {
    $fs = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)

    while($total -lt [UInt64]$MaxBytes){
      $remaining = [int]([Math]::Min([UInt64]$buffer.Length, ([UInt64]$MaxBytes - $total)))
      if($remaining -le 0){ break }

      $read = $fs.Read($buffer,0,$remaining)
      if($read -le 0){ break }

      $total = $total + [UInt64]$read
    }

    $sw.Stop()
    $elapsed = [Math]::Max([double]$sw.Elapsed.TotalMilliseconds, [double]1)
    $mb = ([double]$total / 1048576.0)
    $mbps = $mb / ($elapsed / 1000.0)

    $result.ok = $true
    $result.bytes_read = [UInt64]$total
    $result.elapsed_ms = [UInt64][Math]::Round($elapsed)
    $result.mb_per_second_estimate = [Math]::Round($mbps,4)
    $result.error = ""
  } catch {
    $sw.Stop()
    $result.ok = $false
    $result.elapsed_ms = [UInt64][Math]::Round([Math]::Max([double]$sw.Elapsed.TotalMilliseconds, [double]1))
    $result.error = $_.Exception.Message
  } finally {
    if($null -ne $fs){ $fs.Dispose() }
  }

  return $result
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$volumes = @()
try {
  $volumes = @(Get-Volume -ErrorAction Stop | Sort-Object DriveLetter)
} catch {
  $volumes = @()
}

$rows = @()

foreach($v in @($volumes)){
  $dl = NormalizeDriveLetter (GetProp $v "DriveLetter")
  $fs = SafeStr (GetProp $v "FileSystem")
  $path = SafeStr (GetProp $v "Path")

  $targetRoot = ""
  $probeState = "SKIPPED"
  $sampleFile = ""

  $sample = [ordered]@{
    ok = $false
    bytes_read = [UInt64]0
    elapsed_ms = [UInt64]0
    mb_per_second_estimate = [double]0
    error = ""
  }

  if([string]::IsNullOrWhiteSpace($dl)){
    $probeState = "SKIPPED_NO_DRIVE_LETTER"
    $sample.error = "NO_DRIVE_LETTER"
  } elseif([string]::IsNullOrWhiteSpace($fs)){
    $probeState = "SKIPPED_NO_FILESYSTEM"
    $sample.error = "NO_FILESYSTEM"
  } else {
    $targetRoot = ($dl + ":\")
    $sampleFile = Find-SampleFile -Root $targetRoot -MaxFilesScanned $MaxFilesScanned

    if([string]::IsNullOrWhiteSpace($sampleFile)){
      $probeState = "SKIPPED_NO_SAMPLE_FILE"
      $sample.error = "NO_SAMPLE_FILE"
    } else {
      $sample = Read-Sample -Path $sampleFile -MaxBytes $MaxBytes
      if([bool]$sample.ok){ $probeState = "READ_PROBE_OK" }
      else { $probeState = "READ_PROBE_FAILED" }
    }
  }

  $rows += ,([ordered]@{
    drive_letter = $dl
    path = $path
    file_system = $fs
    label = SafeStr (GetProp $v "FileSystemLabel")
    drive_type = SafeStr (GetProp $v "DriveType")
    health_status = SafeStr (GetProp $v "HealthStatus")
    operational_status = SafeStr (GetProp $v "OperationalStatus")
    size_bytes = SafeU64 (GetProp $v "Size")
    size_remaining_bytes = SafeU64 (GetProp $v "SizeRemaining")
    probe_state = $probeState
    sample_root = $targetRoot
    sample_file = $sampleFile
    max_bytes = [int]$MaxBytes
    max_files_scanned = [int]$MaxFilesScanned
    read_ok = [bool]$sample.ok
    bytes_read = [UInt64]$sample.bytes_read
    elapsed_ms = [UInt64]$sample.elapsed_ms
    mb_per_second_estimate = [double]$sample.mb_per_second_estimate
    error = SafeStr $sample.error
  })
}

$okCount = 0
foreach($r in @($rows)){
  if([bool]$r.read_ok){ $okCount++ }
}

$receipt = [ordered]@{
  schema = "ld.device.read_probe.receipt.v1"
  event_type = "ld.device.read_probe.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "mounted_volume_read_sample"
  destructive = $false
  write_test = $false
  volume_count = [int]$rows.Count
  read_ok_count = [int]$okCount
  rows = @($rows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_read_probe"
EnsureDir $outDir
$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$outPath = Join-Path $outDir ("read_probe_" + $stamp + ".json")

$json = $receipt | ConvertTo-Json -Depth 80 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_READ_PROBE_PATH: " + $outPath)
Write-Output ("DEVICE_READ_PROBE_VOLUME_COUNT: " + [string]$rows.Count)
Write-Output ("DEVICE_READ_PROBE_OK_COUNT: " + [string]$okCount)
Write-Output $json
Write-Output "LD_DEVICE_READ_PROBE_OK"
