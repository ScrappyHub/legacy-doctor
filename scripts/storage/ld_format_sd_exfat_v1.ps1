param(
  [Parameter(Mandatory=$true)][int]$SizeGB,
  [Parameter(Mandatory=$true)][string]$NameLike,
  [Parameter(Mandatory=$true)][string]$IUnderstand
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function PickDisk([int]$SizeGB,[string]$NameLike){
  $min=[int]([Math]::Floor($SizeGB*0.90))
  $max=[int]([Math]::Ceiling($SizeGB*1.10))
  $ds = Get-Disk | Where-Object { $_.FriendlyName -like ("*" + $NameLike + "*") }
  $hits=@()
  foreach($d in @($ds)){
    $gb=[int][Math]::Round($d.Size/1GB)
    if($gb -ge $min -and $gb -le $max){ $hits += ,$d }
  }
  if(@($hits).Count -ne 1){
    Write-Host "DISK_PICK_FAIL: expected exactly 1 match." -ForegroundColor Red
    Write-Host ("NameLike=" + $NameLike + " SizeGB~=" + $SizeGB + " range=" + $min + "-" + $max) -ForegroundColor Yellow
    Get-Disk | Sort-Object Number | Format-Table Number,FriendlyName,Size,PartitionStyle | Out-String | Write-Host
    Die "DISK_PICK_FAIL"
  }
  return $hits[0]
}
$d = PickDisk -SizeGB $SizeGB -NameLike $NameLike
Write-Host ("PICKED_DISK: #" + $d.Number + " " + $d.FriendlyName + " size=" + $d.Size) -ForegroundColor Cyan
if($IUnderstand -ne ("ERASE_DISK_" + $d.Number)){
  Die ("SAFETY_BLOCK: pass -IUnderstand ERASURE token exactly: ERASE_DISK_" + $d.Number)
}
$part = $null
$parts = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
if(@($parts).Count -ge 1){ $part = $parts | Sort-Object PartitionNumber | Select-Object -First 1 }
if($null -eq $part){
  # Create one partition if none
  Initialize-Disk -Number $d.Number -PartitionStyle MBR -ErrorAction Stop | Out-Null
  $part = New-Partition -DiskNumber $d.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
} else {
  if(-not $part.DriveLetter){ $part = $part | Set-Partition -NewDriveLetter (Get-AvailableDriveLetter) -ErrorAction Stop }
}
$letter = (Get-Partition -DiskNumber $d.Number | Where-Object { $_.DriveLetter } | Select-Object -First 1).DriveLetter
if(-not $letter){ Die "NO_DRIVE_LETTER_ASSIGNED" }
Write-Host ("FORMAT_EXFAT: " + $letter + ":") -ForegroundColor Cyan
Format-Volume -DriveLetter $letter -FileSystem exFAT -NewFileSystemLabel "SDCARD" -Force -Confirm:$false | Out-Null
Write-Host ("FORMAT_OK: exFAT " + $letter + ":") -ForegroundColor Green
