param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DriveLetter = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# READ-ONLY device profiler. Never writes to any device; writes one receipt under the repo proofs folder.
function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }

function Get-DeviceKind([string]$Root){
  $has = { param($p) Test-Path -LiteralPath (Join-Path $Root $p) }
  if(& $has "iPod_Control"){
    if(& $has "iPod_Control\iTunes\iTunesDB"){ return "IPOD_MASS_STORAGE" }
    return "IPOD_MASS_STORAGE_NO_DB"
  }
  if(& $has "DCIM"){ return "CAMERA_OR_PHONE_MEDIA" }
  if((& $has "MUSIC") -or (& $has "Music")){ return "GENERIC_MP3_PLAYER" }
  return "GENERIC_VOLUME"
}

function Get-FileCounts([string]$Root,[int]$Cap){
  $audio = @(".mp3",".m4a",".m4b",".aac",".wav",".flac",".ogg",".wma",".aif",".aiff",".mp4",".m4v")
  $n = 0; $a = 0; $bytes = [Int64]0; $capped = $false
  foreach($f in Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue){
    $n++; $bytes += $f.Length
    if($audio -contains $f.Extension.ToLowerInvariant()){ $a++ }
    if($n -ge $Cap){ $capped = $true; break }
  }
  return [pscustomobject]@{ files=$n; audio_files=$a; bytes=$bytes; capped=$capped }
}

$rows = @()
foreach($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -in @("Removable","Fixed","CD-ROM") }){
  $dl = [string]$v.DriveLetter
  if($DriveLetter -and $dl -ne $DriveLetter.TrimEnd(":")){ continue }
  if(-not $DriveLetter -and $v.DriveType -eq "Fixed"){ continue }
  $root = $dl + ":\"
  $ready = Test-Path -LiteralPath $root
  $kind = "UNREADABLE"; $counts = $null; $sysinfo = ""
  if($ready){
    $kind = Get-DeviceKind $root
    $counts = Get-FileCounts $root 50000
    $si = Join-Path $root "iPod_Control\Device\SysInfo"
    if(Test-Path -LiteralPath $si){ $sysinfo = (Get-Content -LiteralPath $si -TotalCount 40 -ErrorAction SilentlyContinue) -join "; " }
  }
  $rows += [pscustomobject]@{
    drive_letter=$dl; label=[string]$v.FileSystemLabel; file_system=[string]$v.FileSystem
    drive_type=[string]$v.DriveType; health=[string]$v.HealthStatus
    size_bytes=[Int64]$v.Size; free_bytes=[Int64]$v.SizeRemaining
    kind=$kind; counts=$counts; ipod_sysinfo=$sysinfo
  }
}

$outDir = Join-Path $RepoRoot "proofs\device_profile"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = Join-Path $outDir ("device_profile_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + ".json")
$doc = [pscustomobject]@{ schema="ld.device.profile.v1"; read_only=$true; created_utc=(Get-Date).ToUniversalTime().ToString("o"); devices=$rows }
[IO.File]::WriteAllText($out, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
$rows | Format-List
"DEVICE_PROFILE_RECEIPT: " + $out
"LD_DEVICE_PROFILE_OK devices=" + $rows.Count
