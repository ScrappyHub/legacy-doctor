param(
  [string]$DriveLetter = "D",
  [string]$Match = "iPod|Apple",
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Obj([string]$title, $data) {
  [pscustomobject]@{ title = $title; data = $data }
}

$dl = $DriveLetter.Trim().TrimEnd(":").ToUpperInvariant()

$sections = @()

# Disks
$disks = Get-Disk | Select-Object Number,FriendlyName,BusType,OperationalStatus,Size
$sections += Obj "Get-Disk" $disks

# Volumes
$vols = Get-Volume | Select-Object DriveLetter,FileSystemLabel,FileSystemType,HealthStatus,OperationalStatus,Size,SizeRemaining
$sections += Obj "Get-Volume" $vols

# PnP matches
$pnp = Get-PnpDevice -PresentOnly |
  Where-Object { $_.FriendlyName -match $Match } |
  Select-Object Status,Class,FriendlyName,InstanceId
$sections += Obj "Get-PnpDevice (match)" $pnp

# Drive-letter specific volume (safe; may not exist)
$dlVol = $null
try {
  $dlVol = Get-Volume -DriveLetter $dl |
    Select-Object DriveLetter,FileSystemLabel,FileSystemType,HealthStatus,OperationalStatus,Size,SizeRemaining
} catch {
  $dlVol = $null
}
$sections += Obj "Get-Volume -DriveLetter $dl" $dlVol

# Quick recommendations
$reco = @()

if (-not $pnp -or $pnp.Count -eq 0) {
  $reco += "No PnP device matches '$Match'. Try a different USB port/cable, then rerun."
} else {
  $reco += "PnP device detected. If no drive letter appears, device may be WPD/MTP or needs driver refresh."
}

if (-not $dlVol) {
  $reco += "No volume for drive letter ${dl}:. If Windows isn't assigning a letter, use Disk Management or diskpart."
} else {
  if (($dlVol.FileSystemType -eq $null) -or ($dlVol.FileSystemType -eq "Unknown") -or ($dlVol.Size -eq 0)) {
    $reco += "Drive letter exists but volume looks 'Unknown' or size=0. Try replug, then chkdsk, then driver refresh."
  }
}

$reco += "Driver refresh (manual): Device Manager -> Disk drives -> Apple iPod USB Device -> Uninstall device (check 'Delete driver' only if needed) -> Action -> Scan for hardware changes."
$reco += "Rescan storage (PowerShell): 'Get-PnpDevice -PresentOnly | Out-Null' and replug."
$reco += "Repair check (FAT): 'chkdsk ${dl}: /f' (run in elevated shell)."

$sections += Obj "Recommendations" $reco

if ($AsJson) {
  $sections | ConvertTo-Json -Depth 6
} else {
  foreach ($s in $sections) {
    ""
    "=== {0} ===" -f $s.title
    $s.data
  }
}
