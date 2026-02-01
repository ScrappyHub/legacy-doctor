param([Parameter(Mandatory=$true)][string]$Scorer)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function WriteUtf8NoBom([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$Text,$enc)
}

if(-not (Test-Path -LiteralPath $Scorer)) { throw ("MISSING_SCORER: " + $Scorer) }

# Backup once
$bak = ($Scorer + ".bak")
if(-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $Scorer -Destination $bak -Force }

$lines = Get-Content -LiteralPath $Scorer
$changed = 0

# Build literal "$rxName = '...'" lines WITHOUT referencing $rxName as a variable
$dlr = [char]36  # $
$r1 = $dlr + "rxStampOut     = '(?im)\bStampOut\b'"
$r2 = $dlr + "rxObs1         = '(?im)Stamped clean scripts found:\s*\{0\}'"
$r3 = $dlr + "rxObs2         = '(?im)Keep threshold:\s*\{0\}'"
$r4 = $dlr + "rxObs3         = '(?im)No prune needed\.'"
$r5 = $dlr + "rxRemovedLines = '(?im)Removed:\s*\{0\}[\s\S]*RemovedPct:\s*\{0\}%[\s\S]*KeptPct:\s*\{0\}%'"

for($i=0; $i -lt $lines.Count; $i++){
  $ln = $lines[$i]
  if($ln -match '^\s*\$rxStampOut\s*='){     $lines[$i] = $r1; $changed++; continue }
  if($ln -match '^\s*\$rxObs1\s*='){         $lines[$i] = $r2; $changed++; continue }
  if($ln -match '^\s*\$rxObs2\s*='){         $lines[$i] = $r3; $changed++; continue }
  if($ln -match '^\s*\$rxObs3\s*='){         $lines[$i] = $r4; $changed++; continue }
  if($ln -match '^\s*\$rxRemovedLines\s*='){ $lines[$i] = $r5; $changed++; continue }
}

if($changed -eq 0){ Write-Host "WARN: no rx* lines updated" -ForegroundColor Yellow }
else { Write-Host ("UPDATED rx* lines: {0}" -f $changed) -ForegroundColor Green }

$raw2 = ($lines -join "`r`n") + "`r`n"
WriteUtf8NoBom $Scorer $raw2
Write-Host ("PATCHED: rx library written UTF8(noBOM): {0}" -f $Scorer) -ForegroundColor Green
Write-Host "NOTE: run scorer to confirm." -ForegroundColor Cyan