param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$Code,[string]$Detail){throw($Code+":"+$Detail)}
function Require([bool]$Condition,[string]$Code,[string]$Detail){if(-not$Condition){Die $Code $Detail}}
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}

# Fail-closed proof for ld_raw_image_acquire_v1.ps1 and ld_optical_image_acquire_v1.ps1.
# Neither script is run with -Execute, and both are pointed at a source that does not exist.
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$root=Join-Path $RepoRoot "proofs\selftest\acquire_failclosed"
if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
EnsureDir $root

function Invoke-Script([string]$Script,[string[]]$ScriptArgs){
  $all=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Script)+$ScriptArgs
  $stdout=Join-Path $root ([IO.Path]::GetFileNameWithoutExtension($Script)+".stdout.txt")
  $stderr=Join-Path $root ([IO.Path]::GetFileNameWithoutExtension($Script)+".stderr.txt")
  $process=Start-Process -FilePath "powershell.exe" -ArgumentList $all -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $out=""
  if(Test-Path -LiteralPath $stdout){$out=[IO.File]::ReadAllText($stdout)}
  return [pscustomobject]@{exit_code=[int]$process.ExitCode;output=$out}
}

function Get-Receipt([string]$Output){
  foreach($line in @($Output -split "`n")){
    $trimmed=$line.Trim()
    if($trimmed.StartsWith("{") -and $trimmed.EndsWith("}")){ return ($trimmed | ConvertFrom-Json) }
  }
  return $null
}

# A refusal is either a non-zero exit or a receipt that shows nothing was allowed or written.
function Assert-Refused([string]$Name,[object]$Result,[string]$Destination){
  if($Result.exit_code -eq 0){
    $receipt=Get-Receipt $Result.output
    Require ($null -ne $receipt) ($Name+"_NO_RECEIPT") $Result.output
    Require (-not [bool]$receipt.execute_requested) ($Name+"_EXECUTE_UNEXPECTED") ""
    Require (-not [bool]$receipt.execution_allowed) ($Name+"_EXECUTION_ALLOWED") ""
    Require (-not [bool]$receipt.writes_destination) ($Name+"_WROTE_DESTINATION_RECEIPT") ""
    Require (@($receipt.blockers).Count -gt 0) ($Name+"_NO_BLOCKERS") ""
  }
  Require (-not (Test-Path -LiteralPath $Destination)) ($Name+"_WROTE_DESTINATION") $Destination
  Require (-not (Test-Path -LiteralPath ($Destination+".legacy-doctor.partial"))) ($Name+"_LEFT_PARTIAL") $Destination
}

# Raw image: a disk number that cannot exist must be refused before any destination write.
$rawDestination=Join-Path $root "raw\image.bin"
$raw=Invoke-Script (Join-Path $RepoRoot "scripts\storage\ld_raw_image_acquire_v1.ps1") @("-RepoRoot",('"'+$RepoRoot+'"'),"-DiskNumber","99999","-ExpectedSizeBytes","1048576","-ExpectedSerialNumber","NOT-A-REAL-SERIAL","-DestinationPath",('"'+$rawDestination+'"'),"-MaxBytes","1048576")
Assert-Refused "RAW_ACQUIRE" $raw $rawDestination

# Optical image: pick a drive letter with no mounted drive.
$used=@([IO.DriveInfo]::GetDrives()|ForEach-Object{([string]$_.Name).Substring(0,1).ToUpperInvariant()})
$letter=@("Z","Y","X","W","V","U"|Where-Object{$used -notcontains $_}|Select-Object -First 1)
Require ($letter.Count -eq 1) "NO_UNUSED_DRIVE_LETTER" ($used -join ",")
$opticalDestination=Join-Path $root "optical\disc.iso"
$optical=Invoke-Script (Join-Path $RepoRoot "scripts\storage\ld_optical_image_acquire_v1.ps1") @("-RepoRoot",('"'+$RepoRoot+'"'),"-DriveLetter",[string]$letter[0],"-DestinationPath",('"'+$opticalDestination+'"'))
Assert-Refused "OPTICAL_ACQUIRE" $optical $opticalDestination

Write-Output "PASS: raw image acquisition refuses a nonexistent disk without writing"
Write-Output "PASS: optical image acquisition refuses an absent drive without writing"
Write-Output "SELFTEST_LD_ACQUIRE_FAILCLOSED_OK"
