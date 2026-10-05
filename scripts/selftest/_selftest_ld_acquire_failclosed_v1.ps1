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

# Raw image: a disk number that cannot exist must be refused before any destination write.
$rawDestination=Join-Path $root "raw\image.bin"
$raw=Invoke-Script (Join-Path $RepoRoot "scripts\storage\ld_raw_image_acquire_v1.ps1") @("-RepoRoot",('"'+$RepoRoot+'"'),"-DiskNumber","99999","-ExpectedSizeBytes","1048576","-ExpectedSerialNumber","NOT-A-REAL-SERIAL","-DestinationPath",('"'+$rawDestination+'"'),"-MaxBytes","1048576")
Require (-not $raw.output.Contains("LD_RAW_IMAGE_ACQUIRE_OK")) "RAW_ACQUIRE_REPORTED_SUCCESS" $raw.output
Require ($raw.exit_code -ne 0 -or $raw.output.Contains("LD_RAW_IMAGE_ACQUIRE_BLOCKED")) "RAW_ACQUIRE_NOT_REFUSED" ([string]$raw.exit_code)
Require (-not (Test-Path -LiteralPath $rawDestination)) "RAW_ACQUIRE_WROTE_DESTINATION" $rawDestination
Require (-not (Test-Path -LiteralPath ($rawDestination+".legacy-doctor.partial"))) "RAW_ACQUIRE_LEFT_PARTIAL" $rawDestination

# Optical image: pick a drive letter with no mounted drive.
$used=@([IO.DriveInfo]::GetDrives()|ForEach-Object{([string]$_.Name).Substring(0,1).ToUpperInvariant()})
$letter=@("Z","Y","X","W","V","U"|Where-Object{$used -notcontains $_}|Select-Object -First 1)
Require ($letter.Count -eq 1) "NO_UNUSED_DRIVE_LETTER" ($used -join ",")
$opticalDestination=Join-Path $root "optical\disc.iso"
$optical=Invoke-Script (Join-Path $RepoRoot "scripts\storage\ld_optical_image_acquire_v1.ps1") @("-RepoRoot",('"'+$RepoRoot+'"'),"-DriveLetter",[string]$letter[0],"-DestinationPath",('"'+$opticalDestination+'"'))
Require (-not $optical.output.Contains("LD_OPTICAL_IMAGE_ACQUIRE_OK")) "OPTICAL_ACQUIRE_REPORTED_SUCCESS" $optical.output
Require ($optical.exit_code -ne 0 -or $optical.output.Contains("LD_OPTICAL_IMAGE_ACQUIRE_BLOCKED")) "OPTICAL_ACQUIRE_NOT_REFUSED" ([string]$optical.exit_code)
Require (-not (Test-Path -LiteralPath $opticalDestination)) "OPTICAL_ACQUIRE_WROTE_DESTINATION" $opticalDestination
Require (-not (Test-Path -LiteralPath ($opticalDestination+".legacy-doctor.partial"))) "OPTICAL_ACQUIRE_LEFT_PARTIAL" $opticalDestination

Write-Output "PASS: raw image acquisition refuses a nonexistent disk without writing"
Write-Output "PASS: optical image acquisition refuses an absent drive without writing"
Write-Output "SELFTEST_LD_ACQUIRE_FAILCLOSED_OK"
