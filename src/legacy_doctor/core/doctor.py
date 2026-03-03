import json
import subprocess
from legacy_doctor.models.doctor import DoctorReport, DoctorSection

def _run_pwsh_json(cmd: str):
    ps = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", cmd
    ]
    out = subprocess.check_output(ps, text=True, stderr=subprocess.STDOUT).strip()
    if not out:
        return None
    return json.loads(out)

def doctor_usb_report(drive_letter: str | None = None, match: str = "iPod|Apple") -> DoctorReport:
    dl = None
    if drive_letter:
        dl = drive_letter.strip().rstrip(":").upper()

    # Build report using PowerShell, returning JSON per section
    cmd = rf"""
$ErrorActionPreference="Stop";

function Sec([string]$title, $data) {{
  [pscustomobject]@{{ title = $title; data = $data }}
}}

$match = {json.dumps(match)};
$dl = {json.dumps(dl or "")};

$sections = @()

$disks = Get-Disk | Select-Object Number,FriendlyName,BusType,OperationalStatus,Size
$sections += Sec "Get-Disk" $disks

$vols = Get-Volume | Select-Object DriveLetter,FileSystemLabel,FileSystemType,HealthStatus,OperationalStatus,Size,SizeRemaining
$sections += Sec "Get-Volume" $vols

$pnp = Get-PnpDevice -PresentOnly | Where-Object {{ $_.FriendlyName -match $match }} | Select-Object Status,Class,FriendlyName,InstanceId
$sections += Sec "Get-PnpDevice (match)" $pnp

$dlVol = $null
if ($dl -and $dl.Length -eq 1) {{
  try {{
    $dlVol = Get-Volume -DriveLetter $dl | Select-Object DriveLetter,FileSystemLabel,FileSystemType,HealthStatus,OperationalStatus,Size,SizeRemaining
  }} catch {{
    $dlVol = $null
  }}
}}
$sections += Sec ("Get-Volume -DriveLetter " + $dl) $dlVol

$reco = @()
if (-not $pnp -or $pnp.Count -eq 0) {{
  $reco += ("No PnP device matches '" + $match + "'. Try a different USB port/cable, then rerun.")
}} else {{
  $reco += "PnP device detected. If no drive letter appears, device may be WPD/MTP or needs driver refresh."
}}

if ($dl -and (-not $dlVol)) {{
  $reco += ("No volume for drive letter " + $dl + ":. Use Disk Management or diskpart if Windows isn't assigning one.")
}}
if ($dlVol) {{
  if (($dlVol.FileSystemType -eq $null) -or ($dlVol.FileSystemType -eq "Unknown") -or ($dlVol.Size -eq 0)) {{
    $reco += "Drive letter exists but volume looks 'Unknown' or size=0. Try replug, then chkdsk, then driver refresh."
  }}
}}

$reco += "Driver refresh (manual): Device Manager -> Disk drives -> Apple iPod USB Device -> Uninstall device -> Action -> Scan for hardware changes."
$reco += "Repair check (FAT): chkdsk X: /f  (run elevated)."

$sections += Sec "Recommendations" $reco

$sections | ConvertTo-Json -Depth 6
"""
    sections_raw = _run_pwsh_json(cmd) or []
    report = DoctorReport(drive_letter=dl, match=match)
    for s in sections_raw:
        report.sections.append(DoctorSection(title=s.get("title",""), data=s.get("data")))
    return report
