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

# 1) Replace exact param block (from introspect)
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
$ix = $txt.IndexOf($oldParam)
if($ix -lt 0){ Die 'PARAM_BLOCK_NOT_FOUND (header drift)' }
$txt = $txt.Substring(0,$ix) + $newParam + $txt.Substring($ix + $oldParam.Length)

# 2) Inject helpers after StrictMode line
$strict = 'Set-StrictMode -Version Latest'
$sx = $txt.IndexOf($strict)
if($sx -lt 0){ Die 'STRICTMODE_ANCHOR_NOT_FOUND' }
$sp = $sx + $strict.Length
$helper = @(
'',
'function IsAdmin(){',
'  $id = [Security.Principal.WindowsIdentity]::GetCurrent()',
'  $p  = New-Object Security.Principal.WindowsPrincipal($id)',
'  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
'}',
'',
'function QuoteWinArg([string]$s){',
'  $q  = [char]34',
'  $bs = [char]92',
'  if($null -eq $s){ return ($q.ToString()+$q.ToString()) }',
'  $t = [string]$s',
'  # escape quotes as \" using char codes (avoid literal \" in source generator)',
'  $esc = $bs.ToString() + $q.ToString()',
'  $t = $t.Replace($q.ToString(), $esc)',
'  return $q.ToString() + $t + $q.ToString()',
'}',
'',
'function RelaunchElevated([hashtable]$bp){',
'  $exe = (Get-Command powershell.exe -ErrorAction Stop).Source',
'  $file = $PSCommandPath',
'  $keys = @(@($bp.Keys) | ForEach-Object { [string]$_ } | Sort-Object)',
'  $parts = New-Object System.Collections.Generic.List[string]',
'  [void]$parts.Add('-NoProfile')',
'  [void]$parts.Add('-ExecutionPolicy') ; [void]$parts.Add('Bypass')',
'  [void]$parts.Add('-File') ; [void]$parts.Add((QuoteWinArg $file))',
'  foreach($k in $keys){',
'    $v = $bp[$k]',
'    if($v -is [bool]){ if($v){ [void]$parts.Add('-'+$k) } ; continue }',
'    if($null -eq $v){ continue }',
'    [void]$parts.Add('-'+$k) ; [void]$parts.Add((QuoteWinArg ([string]$v)))',
'  }',
'  $argLine = ($parts.ToArray() -join ' ')',
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
$txt = $txt.Substring(0,$sp) + "`n" + $helper + $txt.Substring($sp)

# 3) Wire Plan/WhatIf and replace admin block
$wireAnchor = 'if($Cmd -ne "format"){ Die ("UNKNOWN_CMD: " + $Cmd) }'
$w = $txt.IndexOf($wireAnchor)
if($w -lt 0){ Die 'WIRE_ANCHOR_NOT_FOUND' }
$wireInsert = @(
'',
'# Plan/WhatIf mode: never touch disk; emits deterministic plan receipt.',
'if($WhatIf){ $Plan = $true }',
'$isAdmin = IsAdmin',
$start = $txt.IndexOf($oldAdminStart)
if($start -lt 0){ Die 'ADMIN_BLOCK_START_NOT_FOUND' }
$needle = 'if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ Die "ADMIN_REQUIRED: run PowerShell as Administrator for format operations" }'
$endPos = $txt.IndexOf($needle, $start)
if($endPos -lt 0){ Die 'ADMIN_DIE_LINE_NOT_FOUND' }
$end = $endPos + $needle.Length
$newAdmin = @(
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
$fmt = 'schema="storage.receipt.v1"; action="format";'
$fa = $txt.IndexOf($fmt)
if($fa -ge 0){ $txt = $txt.Substring(0,$fa) + 'schema="storage.receipt.v1"; action="format"; run_elevated=$true;' + $txt.Substring($fa + $fmt.Length) }

$final = $txt + "`n"
WriteUtf8Lf $Target $final
ParseGateFile $Target
Write-Host ('PATCH_OK: ' + $Target) -ForegroundColor Green
