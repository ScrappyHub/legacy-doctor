param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetRoot,
  [Int64]$TestBytes = 0,
  [Int64]$ReserveBytes = 33554432,
  [int]$ChunkBytes = 1048576,
  [Int64]$FileBytes = 67108864,
  [Int64]$SimulatedAdvertisedBytes = 0,
  [Int64]$SimulatedRealBytes = 0,
  [switch]$AcceptHealthWarning,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Free-space-only capacity integrity test (H2testw-style).
# Writes position-keyed pseudo-random blocks ONLY into new files it creates in free space, reads them back,
# and compares. It never opens, modifies, or deletes an existing file. It deletes only files it created.
# It cannot detect a fake on space that is already occupied by existing data; the receipt says so.

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }

$ReceiptsLib = Join-Path $PSScriptRoot "_lib_ld_receipts_v1.ps1"
if(-not (Test-Path -LiteralPath $ReceiptsLib -PathType Leaf)){ Die "RECEIPT_LIBRARY_MISSING" $ReceiptsLib }
. $ReceiptsLib

function EnsureDir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  EnsureDir (Split-Path -Parent $Path)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}
function Add-Unique([object[]]$Items,[string]$Value){
  $r = @($Items)
  if(-not ($r -contains $Value)){ $r += $Value }
  return ,@($r)
}
function CanonicalPath([string]$Path){ return [IO.Path]::GetFullPath($Path).TrimEnd("\") }
function IsUnder([string]$Path,[string]$Parent){
  $p = (CanonicalPath $Path) + "\"
  $q = (CanonicalPath $Parent) + "\"
  return $p.StartsWith($q,[StringComparison]::OrdinalIgnoreCase)
}
function HasReparsePoint([string]$Path){
  try {
    $current = [IO.Path]::GetFullPath($Path)
    while(-not [string]::IsNullOrWhiteSpace($current)){
      if(Test-Path -LiteralPath $current){
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ return $true }
      }
      $parent = Split-Path -Parent $current
      if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current){ break }
      $current = $parent
    }
    return $false
  } catch { return $true }
}

if(-not ("LdCapacity" -as [type])){
  Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class LdCapacity {
  static ulong Mix(ulong z){
    unchecked {
      z += 0x9E3779B97F4A7C15UL;
      z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
      z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
      return z ^ (z >> 31);
    }
  }
  public static void FillBlock(byte[] buf, int count, ulong seed, long blockIndex){
    unchecked {
      int words = count / 8;
      ulong baseKey = seed + (ulong)blockIndex * (ulong)words;
      for(int i = 0; i < words; i++){
        ulong v = Mix(baseKey + (ulong)i);
        int o = i * 8;
        buf[o] = (byte)v; buf[o+1] = (byte)(v >> 8); buf[o+2] = (byte)(v >> 16); buf[o+3] = (byte)(v >> 24);
        buf[o+4] = (byte)(v >> 32); buf[o+5] = (byte)(v >> 40); buf[o+6] = (byte)(v >> 48); buf[o+7] = (byte)(v >> 56);
      }
    }
  }
  public static int FirstDiff(byte[] a, byte[] b, int count){
    for(int i = 0; i < count; i++){ if(a[i] != b[i]){ return i; } }
    return -1;
  }
}
public sealed class LdDirectReader : IDisposable {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool ReadFile(IntPtr h, IntPtr buf, uint n, out uint read, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool CloseHandle(IntPtr h);
  IntPtr handle; IntPtr raw; IntPtr aligned; int size;
  public LdDirectReader(string path, int blockSize){
    size = blockSize;
    // GENERIC_READ, share read+write, OPEN_EXISTING, FILE_FLAG_NO_BUFFERING | FILE_FLAG_SEQUENTIAL_SCAN
    handle = CreateFileW(path, 0x80000000u, 3u, IntPtr.Zero, 3u, 0x20000000u | 0x08000000u, IntPtr.Zero);
    if(handle == new IntPtr(-1)){ throw new IOException("direct open failed: " + Marshal.GetLastWin32Error()); }
    raw = Marshal.AllocHGlobal(blockSize + 4096);
    long a = (raw.ToInt64() + 4095L) & ~4095L;
    aligned = new IntPtr(a);
  }
  public int Read(byte[] dest){
    uint n;
    if(!ReadFile(handle, aligned, (uint)size, out n, IntPtr.Zero)){ throw new IOException("direct read failed: " + Marshal.GetLastWin32Error()); }
    if(n > 0){ Marshal.Copy(aligned, dest, 0, (int)n); }
    return (int)n;
  }
  public void Dispose(){
    if(handle != IntPtr.Zero && handle != new IntPtr(-1)){ CloseHandle(handle); handle = IntPtr.Zero; }
    if(raw != IntPtr.Zero){ Marshal.FreeHGlobal(raw); raw = IntPtr.Zero; }
  }
}
"@
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$runId = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$selftestRoot = Join-Path $RepoRoot "proofs\selftest"
$simulated = ($SimulatedAdvertisedBytes -gt 0 -or $SimulatedRealBytes -gt 0)

$blockers = @()
$limitations = @("FREE_SPACE_ONLY","EXISTING_DATA_REGIONS_NOT_TESTED")

$targetExists = Test-Path -LiteralPath $TargetRoot -PathType Container
if(-not $targetExists){ $blockers = Add-Unique $blockers "TARGET_ROOT_MISSING" }

$target = ""
if($targetExists){ $target = CanonicalPath (Resolve-Path -LiteralPath $TargetRoot).Path }
$inSelftest = ($targetExists -and (IsUnder $target $selftestRoot))

if($ChunkBytes -lt 4096 -or $ChunkBytes -gt 16777216 -or ($ChunkBytes % 4096) -ne 0){ $blockers = Add-Unique $blockers "CHUNK_BYTES_INVALID" }
if($ChunkBytes -ge 4096 -and ($FileBytes -lt $ChunkBytes -or ($FileBytes % $ChunkBytes) -ne 0)){ $blockers = Add-Unique $blockers "FILE_BYTES_INVALID" }
if($ReserveBytes -lt 0){ $blockers = Add-Unique $blockers "RESERVE_BYTES_INVALID" }
if($TestBytes -lt 0){ $blockers = Add-Unique $blockers "TEST_BYTES_INVALID" }

if($simulated){
  if($SimulatedAdvertisedBytes -le 0 -or $SimulatedRealBytes -le 0 -or $SimulatedRealBytes -gt $SimulatedAdvertisedBytes){ $blockers = Add-Unique $blockers "SIMULATION_ARGS_INVALID" }
  if($targetExists -and -not $inSelftest){ $blockers = Add-Unique $blockers "SIMULATION_ONLY_UNDER_SELFTEST" }
}

$fileSystem = ""; $driveType = ""; $health = ""
$claimedBytes = [Int64]0; $freeBefore = [Int64]0
if($targetExists){
  if(-not $inSelftest -and (IsUnder $target $RepoRoot)){ $blockers = Add-Unique $blockers "REPO_ROOT_TARGET_FORBIDDEN" }
  if(HasReparsePoint $target){ $blockers = Add-Unique $blockers "TARGET_REPARSE_POINT_FORBIDDEN" }
  if($simulated){
    $claimedBytes = $SimulatedAdvertisedBytes
    $freeBefore = $SimulatedAdvertisedBytes
    $fileSystem = "SIMULATED"; $driveType = "Simulated"; $health = "Simulated"
  } else {
    $rootPath = [IO.Path]::GetPathRoot($target)
    if([string]::IsNullOrWhiteSpace($rootPath) -or $rootPath.StartsWith("\\")){
      $blockers = Add-Unique $blockers "TARGET_NOT_LOCAL_DRIVE_LETTER"
    } else {
      try {
        $di = [IO.DriveInfo]::new($rootPath)
        $fileSystem = [string]$di.DriveFormat
        $driveType = [string]$di.DriveType
        $claimedBytes = [Int64]$di.TotalSize
        $freeBefore = [Int64]$di.AvailableFreeSpace
      } catch { $blockers = Add-Unique $blockers "TARGET_VOLUME_UNREADABLE" }
      if(-not $inSelftest){
        if($driveType -eq "Fixed"){ $blockers = Add-Unique $blockers "TARGET_VOLUME_FIXED_FORBIDDEN" }
        $sysDrive = [IO.Path]::GetPathRoot([Environment]::GetFolderPath("Windows"))
        if($rootPath -eq $sysDrive){ $blockers = Add-Unique $blockers "TARGET_VOLUME_SYSTEM_FORBIDDEN" }
      }
      try {
        $vol = Get-Volume -DriveLetter $rootPath.Substring(0,1) -ErrorAction Stop
        $health = [string]$vol.HealthStatus
      } catch { $health = "Unknown" }
      if($health -ne "Healthy" -and -not $AcceptHealthWarning.IsPresent -and -not $inSelftest){ $blockers = Add-Unique $blockers "VOLUME_HEALTH_NOT_HEALTHY" }
    }
  }
}

$plannedBlocks = [Int64]0
if($blockers.Count -eq 0){
  $usable = $freeBefore - $ReserveBytes
  if($TestBytes -gt 0 -and $TestBytes -lt $usable){ $usable = $TestBytes }
  if($usable -ge $ChunkBytes){ $plannedBlocks = [Int64][Math]::Floor($usable / $ChunkBytes) }
  if($plannedBlocks -lt 1){ $blockers = Add-Unique $blockers "NO_FREE_SPACE_TO_TEST" }
}
$plannedBytes = [Int64]($plannedBlocks * $ChunkBytes)

$executionAllowed = ($Execute.IsPresent -and $blockers.Count -eq 0)
$writtenBlocks = [Int64]0
$writeError = ""
$cacheBypassed = $false
$cleanupOk = $true
$verdict = "NOT_RUN"
$state = @{ good = [Int64]0; bad = [Int64]0; first = [Int64]-1; regions = (New-Object System.Collections.Generic.List[object]) }

function Get-BlockDiff([int]$Chunk,[byte[]]$Expected,[byte[]]$Actual,[int]$ReadCount){
  if($ReadCount -lt $Chunk){ return [int]$ReadCount }
  return [int]([LdCapacity]::FirstDiff($Expected,$Actual,$Chunk))
}

function Record-Block([hashtable]$State,[Int64]$BlockIndex,[int]$Chunk,[int]$Diff){
  if($Diff -lt 0){
    $State.good = [Int64]($State.good + 1)
    return
  }
  $State.bad = [Int64]($State.bad + 1)
  $offset = [Int64]($BlockIndex * $Chunk + $Diff)
  if($State.first -lt 0){ $State.first = $offset }
  if($State.regions.Count -lt 32){
    $State.regions.Add([ordered]@{ block_index = [Int64]$BlockIndex; offset = $offset })
  }
}

function Invoke-SimTest([string]$SimPath,[Int64]$Planned,[Int64]$RealBytes,[int]$Chunk,[UInt64]$Seed,[hashtable]$State){
  $buf = New-Object byte[] $Chunk
  $exp = New-Object byte[] $Chunk
  $act = New-Object byte[] $Chunk
  $written = [Int64]0
  $sim = New-Object System.IO.FileStream($SimPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None,$Chunk)
  try {
    $sim.SetLength($RealBytes)
    for($g = [Int64]0; $g -lt $Planned; $g++){
      [LdCapacity]::FillBlock($buf,$Chunk,$Seed,$g)
      $pos = [Int64](($g * $Chunk) % $RealBytes)
      if(($pos + $Chunk) -gt $RealBytes){ $pos = [Int64]0 }
      [void]$sim.Seek($pos,[IO.SeekOrigin]::Begin)
      $sim.Write($buf,0,$Chunk)
      $written = [Int64]($written + 1)
    }
    $sim.Flush($true)
    for($g = [Int64]0; $g -lt $Planned; $g++){
      [LdCapacity]::FillBlock($exp,$Chunk,$Seed,$g)
      $pos = [Int64](($g * $Chunk) % $RealBytes)
      if(($pos + $Chunk) -gt $RealBytes){ $pos = [Int64]0 }
      [void]$sim.Seek($pos,[IO.SeekOrigin]::Begin)
      $n = [int]$sim.Read($act,0,$Chunk)
      $diff = Get-BlockDiff $Chunk $exp $act $n
      Record-Block $State $g $Chunk $diff
    }
  } finally {
    $sim.Dispose()
  }
  return $written
}

function Invoke-RealWrite([string]$TestDir,[Int64]$Planned,[int]$Chunk,[int]$FileBlocks,[UInt64]$Seed,[System.Collections.Generic.List[string]]$Created){
  $buf = New-Object byte[] $Chunk
  $result = @{ written = [Int64]0; error = "" }
  $fileCount = 0
  while(([Int64]$result.written -lt $Planned) -and ([string]$result.error -eq "")){
    $fileCount++
    $p = Join-Path $TestDir ("cap_{0:D6}.bin" -f $fileCount)
    $fs = $null
    try {
      $fs = New-Object System.IO.FileStream($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,$Chunk,[IO.FileOptions]::WriteThrough)
      $Created.Add($p)
    } catch {
      $result.error = "CREATE_FAILED:" + $_.Exception.Message
    }
    if($null -eq $fs){ continue }
    try {
      $n = 0
      while(($n -lt $FileBlocks) -and ([Int64]$result.written -lt $Planned)){
        [LdCapacity]::FillBlock($buf,$Chunk,$Seed,[Int64]$result.written)
        $fs.Write($buf,0,$Chunk)
        $result.written = [Int64]($result.written + 1)
        $n++
      }
      $fs.Flush($true)
    } catch {
      $result.error = "WRITE_FAILED:" + $_.Exception.Message
    } finally {
      $fs.Dispose()
    }
    Write-Host ("progress: wrote_blocks=" + $result.written + "/" + $Planned)
  }
  return $result
}

function Invoke-RealRead([System.Collections.Generic.List[string]]$Created,[Int64]$Written,[int]$Chunk,[int]$FileBlocks,[UInt64]$Seed,[hashtable]$State){
  $exp = New-Object byte[] $Chunk
  $act = New-Object byte[] $Chunk
  $allDirect = $true
  $fileIndex = 0
  foreach($path in $Created){
    $fileIndex++
    Write-Host ("progress: reading_file=" + $fileIndex + "/" + $Created.Count)
    $startBlock = [Int64](($fileIndex - 1) * $FileBlocks)
    $count = [Int64]($Written - $startBlock)
    if($count -gt $FileBlocks){ $count = [Int64]$FileBlocks }
    if($count -le 0){ continue }
    $direct = $null
    $stream = $null
    try { $direct = New-Object LdDirectReader($path,$Chunk) } catch { $direct = $null; $allDirect = $false }
    if($null -eq $direct){
      $stream = New-Object System.IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read,$Chunk)
    }
    try {
      for($k = [Int64]0; $k -lt $count; $k++){
        $g = [Int64]($startBlock + $k)
        [LdCapacity]::FillBlock($exp,$Chunk,$Seed,$g)
        $n = 0
        try {
          if($null -ne $direct){
            $n = [int]$direct.Read($act)
          } else {
            while($n -lt $Chunk){
              $r = [int]$stream.Read($act,$n,$Chunk - $n)
              if($r -le 0){ break }
              $n = $n + $r
            }
          }
        } catch { $n = 0 }
        $diff = Get-BlockDiff $Chunk $exp $act $n
        Record-Block $State $g $Chunk $diff
      }
    } finally {
      if($null -ne $direct){ $direct.Dispose() }
      if($null -ne $stream){ $stream.Dispose() }
    }
  }
  return $allDirect
}

if($executionAllowed){
  $seedBytes = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($runId))
  $seed = [BitConverter]::ToUInt64($seedBytes,0)
  $fileBlocks = [int]($FileBytes / $ChunkBytes)
  $testDir = Join-Path $target ("ld_capacity_test_" + $runId)
  $simPath = Join-Path $target ("ld_capacity_sim_" + $runId + ".bin")
  $created = New-Object System.Collections.Generic.List[string]
  $createdDir = $false

  try {
    if($simulated){
      $created.Add($simPath)
      $writtenBlocks = [Int64](Invoke-SimTest $simPath $plannedBlocks $SimulatedRealBytes $ChunkBytes $seed $state)
    } else {
      EnsureDir $testDir
      $createdDir = $true
      $w = Invoke-RealWrite $testDir $plannedBlocks $ChunkBytes $fileBlocks $seed $created
      $writtenBlocks = [Int64]$w.written
      $writeError = [string]$w.error
      $direct = Invoke-RealRead $created $writtenBlocks $ChunkBytes $fileBlocks $seed $state
      $cacheBypassed = [bool]($direct -and ($created.Count -gt 0))
    }
  } catch {
    if($writeError -eq ""){ $writeError = "UNEXPECTED:" + $_.Exception.Message }
  } finally {
    foreach($cp in $created){
      try { if(Test-Path -LiteralPath $cp -PathType Leaf){ Remove-Item -LiteralPath $cp -Force } } catch { $cleanupOk = $false }
    }
    if($createdDir){
      try { if(Test-Path -LiteralPath $testDir -PathType Container){ Remove-Item -LiteralPath $testDir -Force } } catch { $cleanupOk = $false }
    }
  }

  if([Int64]$state.bad -gt 0){ $verdict = "FAIL_DATA_MISMATCH" }
  elseif(($writeError -ne "") -or ($writtenBlocks -lt $plannedBlocks)){ $verdict = "FAIL_WRITE_ERROR" }
  else { $verdict = "PASS_TESTED_REGION_VERIFIED" }
}
$goodBlocks = [Int64]$state.good
$badBlocks = [Int64]$state.bad
$firstBad = [Int64]$state.first
$badRegions = $state.regions

$status = "blocked"
if($blockers.Count -eq 0 -and -not $Execute.IsPresent){ $status = "dry_run_ready" }
elseif($blockers.Count -eq 0 -and $Execute.IsPresent){
  if($verdict -eq "PASS_TESTED_REGION_VERIFIED" -and $cleanupOk){ $status = "executed_pass" } else { $status = "executed_fail" }
}
$ok = ($status -eq "dry_run_ready" -or $status -eq "executed_pass")
$availability = if($blockers.Count -eq 0){ "available" } else { "blocked" }
$testedFraction = 0.0
if($claimedBytes -gt 0){ $testedFraction = [Math]::Round(([double]($goodBlocks * $ChunkBytes) / [double]$claimedBytes),6) }
if($simulated){ $limitations = Add-Unique $limitations "SIMULATED_DEVICE" }
if($executionAllowed -and -not $simulated -and -not $cacheBypassed){ $limitations = Add-Unique $limitations "READ_BACK_MAY_BE_SERVED_FROM_OS_CACHE" }

$receipt = [ordered]@{
  schema = "ld.device.capacity_test.receipt.v1"
  event_type = "ld.device.capacity_test.receipt.v1"
  ok = [bool]$ok
  availability = $availability
  repo_root = $RepoRoot
  target_root = $target
  mode = "capacity_test"
  destructive = $false
  writes_existing_files = $false
  execute_requested = [bool]$Execute.IsPresent
  execution_allowed = [bool]$executionAllowed
  simulated = [bool]$simulated
  file_system = $fileSystem
  drive_type = $driveType
  volume_health = $health
  claimed_total_bytes = [Int64]$claimedBytes
  free_bytes_before = [Int64]$freeBefore
  planned_bytes = [Int64]$plannedBytes
  chunk_bytes = [int]$ChunkBytes
  file_bytes = [Int64]$FileBytes
  written_bytes = [Int64]($writtenBlocks * $ChunkBytes)
  verified_good_bytes = [Int64]($goodBlocks * $ChunkBytes)
  bad_block_count = [Int64]$badBlocks
  first_bad_offset = [Int64]$firstBad
  tested_fraction_of_claimed = [double]$testedFraction
  read_cache_bypassed = [bool]$cacheBypassed
  cleanup_ok = [bool]$cleanupOk
  write_error = [string]$writeError
  verdict = $verdict
  status = $status
  bad_regions = [object[]]$badRegions.ToArray()
  limitations = @($limitations)
  blockers = @($blockers)
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\capacity_test"
$outPath = Join-Path $outDir ("capacity_test_" + $runId + ".json")
$json = $receipt | ConvertTo-Json -Depth 20 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("CAPACITY_TEST_PATH: " + $outPath)
Write-Output ("CAPACITY_TEST_STATUS: " + $status)
Write-Output $json
if($ok){ Write-Output "LD_CAPACITY_TEST_OK" } else { Write-Output "LD_CAPACITY_TEST_BLOCKED" }
