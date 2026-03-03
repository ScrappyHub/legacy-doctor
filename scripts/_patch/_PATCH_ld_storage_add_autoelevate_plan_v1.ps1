param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){return}; if(-not(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WriteUtf8Lf([string]$path,[string]$text){ EnsureDir (Split-Path -Parent $path); $cr=[char]13; $lf=[char]10; $s=$text.Replace(($cr.ToString()+$lf.ToString()),$lf.ToString()).Replace($cr.ToString(),$lf.ToString()); if(-not $s.EndsWith($lf.ToString())){ $s+=$lf.ToString() }; [IO.File]::WriteAllText($path,$s,(Utf8NoBom)) }
function ParseGateFile([string]$path){ try { [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $path -Encoding UTF8)) } catch { throw ('PARSE_GATE_FAIL: ' + $path + [char]10 + $_.Exception.Message) } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot 'scripts\storage\ld_storage_v1.ps1'
if(-not (Test-Path -LiteralPath $Target)){ Die ('MISSING_TARGET: ' + $Target) }
$txt = Get-Content -Raw -LiteralPath $Target -Encoding UTF8
$txt = ($txt -replace "`r`n","`n") -replace "`r","`n"
if($txt.EndsWith("`n")){ $txt = $txt.Substring(0,$txt.Length-1) }

# ------------------------------
# 1) Patch PARAM BLOCK (add AutoElevate/Plan/WhatIf)
# ------------------------------
$oldParam = @(
'param(',
'  [Parameter(Mandatory=$true)][string]$RepoRoot,',
'  [Parameter(Mandatory=$true)][ValidateSet("list","format")][string]$Cmd,',
'  [string]$DeviceId,',
'  [int]$DiskNumber = -1,',
'  [ValidateSet("fat32","exfat","ntfs")][string]$Fs,',
'  [string]$Label = "SDCARD",',
'  [string]$IUnderstand,',
'  [string]$Fat32ToolPath',
')'
) -join "`n"

$newParam = @(
'param(',
'  [Parameter(Mandatory=$true)][string]$RepoRoot,',
'  [Parameter(Mandatory=$true)][ValidateSet("list","format")][string]$Cmd,',
'  [string]$DeviceId,',
'  [int]$DiskNumber = -1,',
'  [ValidateSet("fat32","exfat","ntfs")][string]$Fs,',
'  [string]$Label = "SDCARD",',
'  [string]$IUnderstand,',
'  [string]$Fat32ToolPath,',
'  [switch]$AutoElevate,',
'  [switch]$Plan,',
'  [switch]$WhatIf',
')'
) -join "`n"

$idx = $txt.IndexOf($oldParam)
if($idx -lt 0){ Die 'PARAM_BLOCK_ANCHOR_NOT_FOUND (unexpected header drift)' }
$txt = $txt.Substring(0,$idx) + $newParam + $txt.Substring($idx + $oldParam.Length)

# ------------------------------
# 2) Insert helper functions: IsAdmin + RelaunchElevated + PlanPrint
#    Anchor: after Set-StrictMode -Version Latest
# ------------------------------
$anchor = 'Set-StrictMode -Version Latest'
$a2 = $txt.IndexOf($anchor)
if($a2 -lt 0){ Die 'ANCHOR_STRICTMODE_NOT_FOUND' }
$insertPos = $a2 + $anchor.Length
$helper = @(
'',
'function IsAdmin(){',
'  $id = [Security.Principal.WindowsIdentity]::GetCurrent()',
'  $p  = New-Object Security.Principal.WindowsPrincipal($id)',
'  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
'}',
'',
'function QuoteArg([string]$s){',
'  if($null -eq $s){ return '""' }',
'  $t = [string]$s',
'  $t = $t.Replace('"','\"')',
'  return '"' + $t + '"' ',
'}',
'',
'function RelaunchElevated([hashtable]$bp){',
'  $exe = (Get-Command powershell.exe -ErrorAction Stop).Source',
'  $file = $PSCommandPath',
'  $keys = @(@($bp.Keys) | ForEach-Object { [string]$_ } | Sort-Object)',
'  $args = New-Object System.Collections.Generic.List[string]',
'  [void]$args.Add('-NoProfile')',
'  [void]$args.Add('-ExecutionPolicy') ; [void]$args.Add('Bypass')',
'  [void]$args.Add('-File') ; [void]$args.Add((QuoteArg $file))',
'  foreach($k in $keys){',
'    $v = $bp[$k]',
'    if($v -is [bool]){ if($v){ [void]$args.Add('-'+$k) } ; continue }',
'    if($null -eq $v){ continue }',
'    [void]$args.Add('-'+$k) ; [void]$args.Add((QuoteArg ([string]$v)))',
'  }',
'  $argLine = ($args.ToArray() -join ' ')',
'  Start-Process -FilePath $exe -Verb RunAs -ArgumentList $argLine | Out-Null',
'}',
'',
'function PrintPlan([object]$d,[string]$deviceId,[string]$fs,[string]$label,[string]$fat32tool){',
'  Write-Host ('PLAN: would format disk #' + $d.Number + ' ("' + $d.FriendlyName + '")') -ForegroundColor Yellow',
'  Write-Host ('PLAN: device_id=' + $deviceId) -ForegroundColor Yellow',
'  Write-Host ('PLAN: steps:') -ForegroundColor Yellow',
'  Write-Host ('  1) Remove all partitions on disk #' + $d.Number) -ForegroundColor Yellow',
'  Write-Host ('  2) Clear-Disk (RemoveData) and Initialize-Disk MBR') -ForegroundColor Yellow',
'  Write-Host ('  3) Create single partition max size + assign drive letter') -ForegroundColor Yellow',
'  Write-Host ('  4) Format ' + $fs + ' label="' + $label + '"') -ForegroundColor Yellow',
'  if($fs -eq 'fat32'){ Write-Host ('     fat32 path: ' + $fat32tool) -ForegroundColor Yellow }',
'}'
) -join "`n"
$txt = $txt.Substring(0,$insertPos) + "`n" + $helper + $txt.Substring($insertPos)

# ------------------------------
# 3) Wire Plan/WhatIf + AutoElevate in format branch
#    Anchor: if($Cmd -ne "format"){ Die ("UNKNOWN_CMD: " + $Cmd) }
# ------------------------------
$wireAnchor = 'if($Cmd -ne "format"){ Die ("UNKNOWN_CMD: " + $Cmd) }'
$w = $txt.IndexOf($wireAnchor)
if($w -lt 0){ Die 'WIRE_ANCHOR_NOT_FOUND (format branch drift)' }
$wireInsert = @(
'$isAdmin = IsAdmin',
$oldAdmin = '# Require elevation (disk ops).' + "`n" + '$id = [Security.Principal.WindowsIdentity]::GetCurrent()'
$pos = $txt.IndexOf($oldAdmin)
if($pos -lt 0){ Die 'ADMIN_BLOCK_ANCHOR_NOT_FOUND' }

# Find the start of admin block and the line just after the Die "ADMIN_REQUIRED..." (we replace the whole block).
$start = $pos
$needle = 'if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ Die "ADMIN_REQUIRED: run PowerShell as Administrator for format operations" }'
$endPos = $txt.IndexOf($needle, $start)
if($endPos -lt 0){ Die 'ADMIN_DIE_LINE_NOT_FOUND' }
$end = $endPos + $needle.Length

$newAdminBlock = @(
'# Require elevation (disk ops) unless Plan/WhatIf. AutoElevate can relaunch with UAC.',
'if($Plan){',
'  $d0 = PickDisk -DeviceId $DeviceId -DiskNumber $DiskNumber',
'  $did0 = MakeDeviceId $d0',
'  PrintPlan -d $d0 -deviceId $did0 -fs $Fs -label $Label -fat32tool $Fat32ToolPath',
'  $objP = [ordered]@{ schema="storage.receipt.v1"; action="plan"; time_utc=[DateTime]::UtcNow.ToString("o"); host=$env:COMPUTERNAME; disk_number=$d0.Number; device_id=$did0; fs=$Fs; label=$Label; auto_elevate=[bool]$AutoElevate }',
'  [void](EmitReceipt $RepoRoot $objP)',
'  return',
'}',
'if(-not $isAdmin){',
'  if($AutoElevate){',
'    $objE = [ordered]@{ schema="storage.receipt.v1"; action="format_elevate_requested"; time_utc=[DateTime]::UtcNow.ToString("o"); host=$env:COMPUTERNAME; cmd=$Cmd; disk_number=$DiskNumber; device_id=$DeviceId; fs=$Fs; label=$Label }',
'    [void](EmitReceipt $RepoRoot $objE)',
'    RelaunchElevated $PSBoundParameters',
'    return',
'  } else {',
'    $objD = [ordered]@{ schema="storage.receipt.v1"; action="format_denied"; time_utc=[DateTime]::UtcNow.ToString("o"); host=$env:COMPUTERNAME; reason="not_admin"; cmd=$Cmd; disk_number=$DiskNumber; device_id=$DeviceId; fs=$Fs; label=$Label }',
'    [void](EmitReceipt $RepoRoot $objD)',
'    Die "ADMIN_REQUIRED: run PowerShell as Administrator for format operations"',
'  }',
'}',
$fmtAnchor = 'schema="storage.receipt.v1"; action="format";'
$fa = $txt.IndexOf($fmtAnchor)
if($fa -ge 0){ $txt = $txt.Substring(0,$fa) + 'schema="storage.receipt.v1"; action="format"; run_elevated=$true;' + $txt.Substring($fa + $fmtAnchor.Length) }

# Write back, parse-gate, done.
$final = $txt + "`n"
WriteUtf8Lf $Target $final
ParseGateFile $Target
Write-Host ('PATCH_OK: ' + $Target) -ForegroundColor Green
