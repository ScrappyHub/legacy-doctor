param([Parameter(Mandatory=$true)][string]$Root)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function WriteUtf8NoBom([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$Text,$enc)
}

function ParseCheck([string]$Path){
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path)) | Out-Null
}

$ScriptsDir = Join-Path $Root "scripts"
$Writer     = Join-Path $ScriptsDir "_write_restore_engine_phase4.ps1"
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null

# ------------------------------------------------------------
# Build WRITER safely: add lines via AddW (auto-escapes quotes)
# ------------------------------------------------------------
$W = @()
function AddW([string]$Line){
  # Convert any text into a safe single-quoted literal for the writer
  $safe = $Line.Replace("'","''")
  $script:W += ("$W += '{0}'" -f $safe)
}

AddW 'param([Parameter(Mandatory=$true)][string]$Root)'
AddW 'Set-StrictMode -Version Latest'
AddW '$ErrorActionPreference="Stop"'
AddW ''
AddW 'function WriteUtf8NoBom([string]$Path,[string]$Text){'
AddW '  $dir = Split-Path -Parent $Path'
AddW '  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }'
AddW '  $enc = New-Object System.Text.UTF8Encoding($false)'
AddW '  [System.IO.File]::WriteAllText($Path,$Text,$enc)'
AddW '}'
AddW ''
AddW 'function ParseCheck([string]$Path){ [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path)) | Out-Null }'
AddW ''
AddW 'function WriteText([string]$Path,[string]$Text){'
AddW '  WriteUtf8NoBom $Path $Text'
AddW '  if ($Path.ToLowerInvariant().EndsWith(".ps1")) { ParseCheck $Path }'
AddW '  Write-Host ("WROTE OK: {0}" -f $Path) -ForegroundColor Green'
AddW '}'
AddW ''
AddW '$rst   = Join-Path $Root "src\engine\restore"'
AddW '$pre   = Join-Path $rst  "preflight"'
AddW '$prov  = Join-Path $rst  "providers"'
AddW '$proto = Join-Path $rst  "protocol"'
AddW '$docs  = Join-Path $Root "docs"'
AddW 'New-Item -ItemType Directory -Force -Path $rst,$pre,$prov,$proto,$docs | Out-Null'
AddW ''
AddW '$L = @()'
AddW '$L += "Set-StrictMode -Version Latest"'
AddW '$L += "$ErrorActionPreference=`"Stop`""'
AddW '$L += ""'
AddW '$L += "[Flags()] enum RestoreRisk {"'
AddW '$L += "  None = 0"'
AddW '$L += "  DiskMismatch = 1"'
AddW '$L += "  PartitionMismatch = 2"'
AddW '$L += "  InsufficientSpace = 4"'
AddW '$L += "  OnBattery = 8"'
AddW '$L += "  LowBattery = 16"'
AddW '$L += "  NoNetwork = 32"'
AddW '$L += "  EncryptedTarget = 64"'
AddW '$L += "  BitLockerUnknown = 128"'
AddW '$L += "  RequiresReboot = 256"'
AddW '$L += "  DangerousModeRequired = 512"'
AddW '$L += "}"'
AddW '$L += ""'
AddW '$L += "class RestorePreflightResult {"'
AddW '$L += "  [bool]$Ok"'
AddW '$L += "  [RestoreRisk]$RiskFlags = [RestoreRisk]::None"'
AddW '$L += "  [string[]]$Warnings = @()"'
AddW '$L += "  [string[]]$Errors = @()"'
AddW '$L += "  [double]$EstimatedMinutes = 0"'
AddW '$L += "  [int]$RequiredReboots = 0"'
AddW '$L += "  [hashtable]$Facts = @{}"'
AddW '$L += "  RestorePreflightResult(){}"'
AddW '$L += "}"'
AddW '$L += ""'
AddW '$L += "class RestorePlan {"'
AddW '$L += "  [string]$RestoreId"'
AddW '$L += "  [string]$BundlePath"'
AddW '$L += "  [string]$TargetDiskId"'
AddW '$L += "  [string]$TargetPartitionId"'
AddW '$L += "  [UInt64]$TargetBytesRequired = 0"'
AddW '$L += "  [string]$Tier = 'consumer'"'
AddW '$L += "  [bool]$DangerousAllowed = $false"'
AddW '$L += "  [string]$NormalizationProfileId = 'default'"'
AddW '$L += "}"'
AddW '$L += ""'
AddW '$L += "[abstract] class SnapshotProviderBase {"'
AddW '$L += "  [string]$Name"'
AddW '$L += "  [string]$Platform"'
AddW '$L += "  SnapshotProviderBase([string]$name,[string]$platform){ $this.Name=$name; $this.Platform=$platform }"'
AddW '$L += "  [abstract] [string] Create([RestorePlan]$plan)"'
AddW '$L += "  [abstract] [void]   Restore([RestorePlan]$plan, [string]$snapshotId)"'
AddW '$L += "  [abstract] [bool]   Verify([RestorePlan]$plan, [string]$snapshotId)"'
AddW '$L += "}"'
AddW 'WriteText (Join-Path $rst "types.ps1") ($L -join "`r`n")'
AddW ''
AddW '$L = @()'
AddW '$L += "Set-StrictMode -Version Latest"'
AddW '$L += "$ErrorActionPreference=`"Stop`""'
AddW '$L += ""'
AddW '$L += ". (Join-Path $PSScriptRoot '..\types.ps1')"'
AddW '$L += ""'
AddW '$L += "function Get-BytesFree([string]$path){ try { $di=New-Object System.IO.DriveInfo($path); [UInt64]$di.AvailableFreeSpace } catch { [UInt64]0 } }"'
AddW '$L += ""'
AddW '$L += "function Get-PowerFactsWindows { $facts=@{}; try { $b=Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1; if($b){$facts.onBattery=$true;$facts.estimatedChargeRemaining=$b.EstimatedChargeRemaining}else{$facts.onBattery=$false} } catch { $facts.onBattery=$false }; $facts }"'
AddW '$L += ""'
AddW '$L += "function Get-NetworkFactsWindows { $facts=@{}; try { $up=Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }; $facts.anyUp=(@($up).Count -gt 0) } catch { $facts.anyUp=$false }; $facts }"'
AddW '$L += ""'
AddW '$L += "function Get-BitLockerFactsWindows([string]$mountPoint){ $facts=@{ known=$false }; try { $v=Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop; $facts.known=$true; $facts.protectionStatus=$v.ProtectionStatus; $facts.volumeStatus=$v.VolumeStatus; $facts.encryptionPercentage=$v.EncryptionPercentage } catch {} ; $facts }"'
AddW '$L += ""'
AddW '$L += "function Test-RestorePreflight([RestorePlan]$plan){"'
AddW '$L += "  $r=[RestorePreflightResult]::new(); $r.Ok=$true"'
AddW '$L += "  if([string]::IsNullOrWhiteSpace($plan.TargetDiskId)){ $r.Ok=$false; $r.Errors+= 'Missing TargetDiskId'; $r.RiskFlags=$r.RiskFlags -bor [RestoreRisk]::DiskMismatch }"'
AddW '$L += "  if(-not (Test-Path -LiteralPath $plan.BundlePath)){ $r.Ok=$false; $r.Errors += ('BundlePath missing: {0}' -f $plan.BundlePath) }"'
AddW '$L += "  $free = Get-BytesFree $plan.BundlePath; $r.Facts.freeBytes=$free"'
AddW '$L += "  if($plan.TargetBytesRequired -gt 0 -and $free -gt 0 -and $free -lt $plan.TargetBytesRequired){ $r.Ok=$false; $r.Errors += ('Insufficient space. Free={0} Required={1}' -f $free,$plan.TargetBytesRequired); $r.RiskFlags=$r.RiskFlags -bor [RestoreRisk]::InsufficientSpace }"'
AddW '$L += "  $pf = Get-PowerFactsWindows; foreach($k in $pf.Keys){ $r.Facts['power.'+$k]=$pf[$k] }"'
AddW '$L += "  if($pf.onBattery -eq $true){ $r.RiskFlags=$r.RiskFlags -bor [RestoreRisk]::OnBattery; if(($pf.estimatedChargeRemaining -is [int]) -and ($pf.estimatedChargeRemaining -lt 30)){ $r.RiskFlags=$r.RiskFlags -bor [RestoreRisk]::LowBattery; $r.Warnings += 'On battery with low charge (<30%). Prefer AC power.' } else { $r.Warnings += 'On battery. Prefer AC power for restore.' } }"'
AddW '$L += "  $nf = Get-NetworkFactsWindows; foreach($k in $nf.Keys){ $r.Facts['net.'+$k]=$nf[$k] }"'
AddW '$L += "  if($nf.anyUp -eq $false){ $r.RiskFlags=$r.RiskFlags -bor [RestoreRisk]::NoNetwork; $r.Warnings += 'No active network adapter. OK offline; remote bundle fetch will fail.' }"'
AddW '$L += "  $bl = Get-BitLockerFactsWindows 'C:'; foreach($k in $bl.Keys){ $r.Facts['bitlocker.'+$k]=$bl[$k] }"'
AddW '$L += "  if($bl.known -eq $false){ $r.RiskFlags=$r.RiskFlags -bor [RestoreRisk]::BitLockerUnknown; $r.Warnings += 'BitLocker status unknown (Get-BitLockerVolume unavailable or failed).' } else { if($bl.protectionStatus -eq 1){ $r.RiskFlags=$r.RiskFlags -bor [RestoreRisk]::EncryptedTarget; $r.Warnings += 'BitLocker protection appears ON. Ensure policy allows encrypted target restore.' } }"'
AddW '$L += "  if($plan.TargetBytesRequired -gt 0){ $bps=150MB; $r.EstimatedMinutes=[math]::Round(($plan.TargetBytesRequired/[double]$bps)/60.0,2) }"'
AddW '$L += "  if($plan.Tier -eq 'dev'){ $r.RequiredReboots=1; $r.RiskFlags=$r.RiskFlags -bor [RestoreRisk]::RequiresReboot }"'
AddW '$L += "  return $r"'
AddW '$L += "}"'
AddW 'WriteText (Join-Path $pre "preflight.ps1") ($L -join "`r`n")'
AddW ''

# --- write writer (UTF8 no BOM) ---
WriteUtf8NoBom $Writer ($W -join "`r`n")
ParseCheck $Writer
Write-Host ("WRITER PARSE OK: {0}" -f $Writer) -ForegroundColor Green

powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Writer -Root $Root