param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DeviceId,
  [int]$DiskNumber = -1,
  [string]$Label = "SDCARD",
  [int]$ClusterKiB = 0,
  [switch]$EmitReceipt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_lib_ld_rawdisk_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_fat32_layout_v1.ps1")

function PLAN-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function PLAN-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function PLAN-Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }

function PLAN-WriteUtf8NoBomLf([string]$path,[string]$text){
  $dir = Split-Path -Parent $path
  if($dir){ PLAN-EnsureDir $dir }
  $t = ($text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($path,$t,(PLAN-Utf8NoBom))
}

function PLAN-AppendUtf8NoBomLf([string]$path,[string]$line){
  $dir = Split-Path -Parent $path
  if($dir){ PLAN-EnsureDir $dir }
  $t = ($line -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($path,$t,(PLAN-Utf8NoBom))
}

function PLAN-Canon($v){
  if($null -eq $v){ return $null }

  if($v -is [string] -or $v -is [int] -or $v -is [long] -or $v -is [uint16] -or $v -is [uint32] -or $v -is [uint64] -or $v -is [double] -or $v -is [decimal] -or $v -is [bool]){
    return $v
  }

  if($v -is [datetime]){
    return $v.ToUniversalTime().ToString("o")
  }

  if($v -is [System.Collections.IDictionary]){
    $keys = @($v.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $o = [ordered]@{}
    foreach($k in $keys){
      $o[$k] = PLAN-Canon $v[$k]
    }
    return $o
  }

  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $a = @()
    foreach($x in $v){
      $a += ,(PLAN-Canon $x)
    }
    return $a
  }

  return ([string]$v)
}

function PLAN-ToCanonJson($v){
  return ((PLAN-Canon $v) | ConvertTo-Json -Depth 50 -Compress)
}

function PLAN-Sha256HexTextLf([string]$s){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes(($s + "`n"))
  return (LD-Sha256Hex $bytes)
}

function PLAN-ReceiptPath([string]$RepoRoot){
  return (Join-Path $RepoRoot "proofs\receipts\storage.ndjson")
}

function PLAN-EmitReceipt([string]$RepoRoot,[hashtable]$Obj){
  $rp = PLAN-ReceiptPath $RepoRoot
  $json = PLAN-ToCanonJson $Obj
  $rh = PLAN-Sha256HexTextLf $json

  $o2 = [ordered]@{}
  foreach($k in $Obj.Keys){ $o2[$k] = $Obj[$k] }
  $o2["receipt_hash"] = $rh

  PLAN-AppendUtf8NoBomLf $rp (PLAN-ToCanonJson $o2)
  return $rh
}

function PLAN-MakeDeviceId($d){
  $u = ""
  try { if($d.UniqueId){ $u = [string]$d.UniqueId } } catch { $u = "" }

  $base = ("disk_number=" + $d.Number + "|unique_id=" + $u + "|size=" + $d.Size + "|name=" + $d.FriendlyName)
  $h = PLAN-Sha256HexTextLf $base

  return ("win.disk.v1:" + $d.Number + ":" + $h)
}

function PLAN-PickDisk([string]$DeviceId,[int]$DiskNumber){
  $ds = @(Get-Disk | Sort-Object Number)

  if($DiskNumber -ge 0){
    $d = $ds | Where-Object { $_.Number -eq $DiskNumber } | Select-Object -First 1
    if(-not $d){ PLAN-Die "DISK_NOT_FOUND" ([string]$DiskNumber) }
    return $d
  }

  if([string]::IsNullOrWhiteSpace($DeviceId)){
    PLAN-Die "MISSING_TARGET" "pass -DiskNumber or -DeviceId"
  }

  $hits = @()
  foreach($d in $ds){
    if((PLAN-MakeDeviceId $d) -eq $DeviceId){
      $hits += ,$d
    }
  }

  if(@($hits).Count -ne 1){
    PLAN-Die "DEVICEID_NOT_UNIQUE_OR_NOT_FOUND" ("count=" + @($hits).Count)
  }

  return $hits[0]
}

function PLAN-SafetyCheck($d){
  if($d.IsBoot){ PLAN-Die "REFUSE_BOOT_DISK" ("disk " + $d.Number) }
  if($d.IsSystem){ PLAN-Die "REFUSE_SYSTEM_DISK" ("disk " + $d.Number) }
}

function PLAN-EmitHumanPlan($summary){
  Write-Host ""
  Write-Host "LEGACY DOCTOR — OWNED FAT32 FORMAT PLAN" -ForegroundColor Cyan
  Write-Host "--------------------------------------------------"
  Write-Host ("DiskNumber        : " + $summary.DiskNumber)
  Write-Host ("DeviceId          : " + $summary.DeviceId)
  Write-Host ("PartitionStyle    : " + $summary.PartitionStyle)
  Write-Host ("PartitionType     : " + $summary.PartitionType)
  Write-Host ("StartLba          : " + $summary.StartLba)
  Write-Host ("SizeLba           : " + $summary.SizeLba)
  Write-Host ("BytesPerSector    : " + $summary.BytesPerSector)
  Write-Host ("SectorsPerCluster : " + $summary.SectorsPerCluster)
  Write-Host ("ClusterSizeBytes  : " + $summary.ClusterSizeBytes)
  Write-Host ("ReservedSectors   : " + $summary.ReservedSectors)
  Write-Host ("FatCount          : " + $summary.FatCount)
  Write-Host ("FatSizeSectors    : " + $summary.FatSizeSectors)
  Write-Host ("ClusterCount      : " + $summary.ClusterCount)
  Write-Host ("RootCluster       : " + $summary.RootCluster)
  Write-Host ("Label             : " + $summary.Label)
  Write-Host ("VolumeSerial      : " + $summary.VolumeSerial)
  Write-Host "--------------------------------------------------"
  Write-Host ""
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

try {
  $disk = PLAN-PickDisk -DeviceId $DeviceId -DiskNumber $DiskNumber
  PLAN-SafetyCheck $disk

  $deviceId = PLAN-MakeDeviceId $disk

  $diskFacts = LD-GetDiskFacts -DiskNumber $disk.Number

  $plan = LDFAT-NewPlan `
    -DiskSizeBytes ([UInt64]$diskFacts.size_bytes) `
    -BytesPerSector ([int]$diskFacts.logical_sector_size) `
    -DeviceId $deviceId `
    -DiskNumber ([int]$disk.Number) `
    -Label $Label `
    -ClusterKiB $ClusterKiB

  $summary = LDFAT-PlanSummary $plan
  $summary | Add-Member -NotePropertyName DeviceId -NotePropertyValue $deviceId -Force

  PLAN-EmitHumanPlan $summary

  $planJson = PLAN-ToCanonJson $plan
  $planHash = PLAN-Sha256HexTextLf $planJson

  Write-Host ("PLAN_SHA256: " + $planHash) -ForegroundColor Yellow
  Write-Host "LD_FAT32_PLAN_READY" -ForegroundColor Green

  if($EmitReceipt){
    $receipt = [ordered]@{
      schema = "storage.receipt.v1"
      action = "plan-fat32-format-owned"
      time_utc = [DateTime]::UtcNow.ToString("o")
      host = $env:COMPUTERNAME
      disk_number = $plan.disk_number
      device_id = $plan.device_id
      label = $plan.volume_label
      cluster_kib = $ClusterKiB
      token = "LD_FAT32_PLAN_READY"
      ok = $true
      plan_sha256 = $planHash
    }

    [void](PLAN-EmitReceipt -RepoRoot $RepoRoot -Obj $receipt)
  }

  exit 0
}
catch {
  $msg = $_.Exception.Message
  Write-Host $msg -ForegroundColor Red

  if($EmitReceipt){
    try {
      $receipt2 = [ordered]@{
        schema = "storage.receipt.v1"
        action = "plan-fat32-format-owned-fail"
        time_utc = [DateTime]::UtcNow.ToString("o")
        host = $env:COMPUTERNAME
        disk_number = $DiskNumber
        device_id = $DeviceId
        label = $Label
        reason = $msg
        ok = $false
      }

      [void](PLAN-EmitReceipt -RepoRoot $RepoRoot -Obj $receipt2)
    } catch { }
  }

  exit 1
}
