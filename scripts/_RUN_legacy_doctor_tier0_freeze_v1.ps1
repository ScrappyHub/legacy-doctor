param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,(Utf8NoBom))
}

function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "SHA256_FILE_MISSING" $Path
  }

  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
  return $h.Hash.ToLower()
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_GATE_MISSING" $Path
  }

  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }
}

function Canon([object]$Value){
  if($null -eq $Value){ return $null }

  if(
    $Value -is [string] -or
    $Value -is [int] -or
    $Value -is [long] -or
    $Value -is [double] -or
    $Value -is [decimal] -or
    $Value -is [bool] -or
    $Value -is [byte] -or
    $Value -is [UInt16] -or
    $Value -is [UInt32] -or
    $Value -is [UInt64]
  ){
    return $Value
  }

  if($Value -is [datetime]){
    return $Value.ToUniversalTime().ToString("o")
  }

  if($Value -is [System.Collections.IDictionary]){
    $keys = @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $o = [ordered]@{}
    foreach($k in $keys){
      $o[$k] = Canon $Value[$k]
    }
    return $o
  }

  if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
    $arr = @()
    foreach($x in @($Value)){
      $arr += ,(Canon $x)
    }
    return ,$arr
  }

  return ([string]$Value)
}

function ToCanonJson([object]$Value){
  return ((Canon $Value) | ConvertTo-Json -Depth 80 -Compress)
}

function Quote-ProcessArg([string]$Value){
  if($null -eq $Value){ $Value = "" }
  return ('"' + ($Value -replace '"','\"') + '"')
}

function Invoke-ChildPowerShellSilent(
  [string]$PSExe,
  [string]$ScriptPath,
  [string]$RepoRoot,
  [string]$StdoutPath,
  [string]$StderrPath
){
  $args = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $ScriptPath,
    "-RepoRoot",
    $RepoRoot
  )

  $argParts = @()
  foreach($a in @($args)){
    $argParts += (Quote-ProcessArg ([string]$a))
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $PSExe
  $psi.Arguments = ($argParts -join " ")
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $RepoRoot

  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi

  [void]$proc.Start()
  $outText = $proc.StandardOutput.ReadToEnd()
  $errText = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()

  Write-Utf8NoBomLf -Path $StdoutPath -Text $outText
  Write-Utf8NoBomLf -Path $StderrPath -Text $errText

  return [ordered]@{
    exit_code = [int]$proc.ExitCode
    stdout = [string]$outText
    stderr = [string]$errText
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$ThisRunner = Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_tier0_freeze_v1.ps1"

$ScriptsToParse = @(
  $ThisRunner,
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_device_probe_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_health_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_acquire_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_extract_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_packet_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_inspect_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_extract_image_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_packetize_case_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_verify_packet_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_inspect_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_backup_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_backup_device_physical_guard_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_verify_image_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_extract_image_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_verify_packet_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_inspect_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_backup_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_verify_image_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_extract_image_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_verify_packet_v1.ps1")
)

$ArtifactsToHash = @(
  (Join-Path $RepoRoot "schemas\ld.device.inspect.receipt.v1.json"),
  (Join-Path $RepoRoot "schemas\ld.device.health.receipt.v1.json"),
  (Join-Path $RepoRoot "schemas\ld.device.backup.receipt.v1.json"),
  (Join-Path $RepoRoot "schemas\ld.device.extract.receipt.v1.json"),
  (Join-Path $RepoRoot "schemas\ld.packet.verify.receipt.v1.json")
)

foreach($p in @($ScriptsToParse)){
  Parse-GateFile $p
  Write-Output ("PARSE_OK: " + $p)
}

foreach($p in @($ArtifactsToHash)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die "ARTIFACT_MISSING" $p
  }
  Write-Output ("ARTIFACT_OK: " + $p)
}

$FreezeRoot = Join-Path $RepoRoot "proofs\receipts\legacy_doctor_tier0_freeze"
EnsureDir $FreezeRoot

$RunId = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$RunDir = Join-Path $FreezeRoot $RunId
EnsureDir $RunDir

$StdoutPath = Join-Path $RunDir "stdout.txt"
$StderrPath = Join-Path $RunDir "stderr.txt"
$MetaPath = Join-Path $RunDir "meta.json"
$ShaPath = Join-Path $RunDir "sha256sums.txt"

$RunnerList = @(
  [ordered]@{
    name = "inspect_device"
    path = (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_inspect_device_v1.ps1")
    must_match = "LEGACY_DOCTOR_INSPECT_DEVICE_ALL_GREEN"
  },
  [ordered]@{
    name = "backup_device"
    path = (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_backup_device_v1.ps1")
    must_match = "LEGACY_DOCTOR_BACKUP_DEVICE_ALL_GREEN"
  },
  [ordered]@{
    name = "verify_image"
    path = (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_verify_image_v1.ps1")
    must_match = "LEGACY_DOCTOR_VERIFY_IMAGE_ALL_GREEN"
  },
  [ordered]@{
    name = "extract_image"
    path = (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_extract_image_v1.ps1")
    must_match = "LEGACY_DOCTOR_EXTRACT_IMAGE_ALL_GREEN"
  },
  [ordered]@{
    name = "verify_packet"
    path = (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_verify_packet_v1.ps1")
    must_match = "LEGACY_DOCTOR_VERIFY_PACKET_ALL_GREEN"
  }
)

$stdoutLines = @()
$stderrLines = @()
$results = @()

foreach($runner in @($RunnerList)){
  $stdoutLines += ("RUNNER_START: " + $runner.name)
  $stdoutLines += ("RUNNER_PATH: " + $runner.path)

  $tmpOut = Join-Path $RunDir ($runner.name + ".stdout.tmp.txt")
  $tmpErr = Join-Path $RunDir ($runner.name + ".stderr.tmp.txt")

  if(Test-Path -LiteralPath $tmpOut){ Remove-Item -LiteralPath $tmpOut -Force }
  if(Test-Path -LiteralPath $tmpErr){ Remove-Item -LiteralPath $tmpErr -Force }

  $child = Invoke-ChildPowerShellSilent `
    -PSExe $PSExe `
    -ScriptPath ([string]$runner.path) `
    -RepoRoot $RepoRoot `
    -StdoutPath $tmpOut `
    -StderrPath $tmpErr

  $outText = [string]$child.stdout
  $errText = [string]$child.stderr
  $exitCode = [int]$child.exit_code

  $stdoutLines += ("RUNNER_EXIT: " + $runner.name + ": " + [string]$exitCode)

  if(-not [string]::IsNullOrWhiteSpace($outText)){
    $stdoutLines += ("RUNNER_STDOUT_BEGIN: " + $runner.name)
    $stdoutLines += $outText
    $stdoutLines += ("RUNNER_STDOUT_END: " + $runner.name)
  }

  if(-not [string]::IsNullOrWhiteSpace($errText)){
    $stderrLines += ("RUNNER_STDERR_BEGIN: " + $runner.name)
    $stderrLines += $errText
    $stderrLines += ("RUNNER_STDERR_END: " + $runner.name)
  }

  if($exitCode -ne 0){
    Write-Utf8NoBomLf -Path $StdoutPath -Text ($stdoutLines -join "`n")
    Write-Utf8NoBomLf -Path $StderrPath -Text ($stderrLines -join "`n")

    Write-Host ("FREEZE_FAIL_RUNNER: " + $runner.name) -ForegroundColor Yellow
    Write-Host ("FREEZE_FAIL_EXIT: " + [string]$exitCode) -ForegroundColor Yellow

    if(-not [string]::IsNullOrWhiteSpace($outText)){
      Write-Host ("FREEZE_FAIL_STDOUT_BEGIN: " + $runner.name) -ForegroundColor Yellow
      [Console]::Out.WriteLine($outText)
      Write-Host ("FREEZE_FAIL_STDOUT_END: " + $runner.name) -ForegroundColor Yellow
    }

    if(-not [string]::IsNullOrWhiteSpace($errText)){
      Write-Host ("FREEZE_FAIL_STDERR_BEGIN: " + $runner.name) -ForegroundColor Yellow
      [Console]::Out.WriteLine($errText)
      Write-Host ("FREEZE_FAIL_STDERR_END: " + $runner.name) -ForegroundColor Yellow
    }

    Die "RUNNER_EXIT_NONZERO" ($runner.name + ":" + [string]$exitCode)
  }

  if($outText -notmatch [regex]::Escape([string]$runner.must_match)){
    Write-Utf8NoBomLf -Path $StdoutPath -Text ($stdoutLines -join "`n")
    Write-Utf8NoBomLf -Path $StderrPath -Text ($stderrLines -join "`n")
    Die "RUNNER_TOKEN_MISSING" $runner.name
  }

  $results += ,([ordered]@{
    name = [string]$runner.name
    path = [string]$runner.path
    exit_code = [int]$exitCode
    token = [string]$runner.must_match
    ok = $true
  })
}

Write-Utf8NoBomLf -Path $StdoutPath -Text ($stdoutLines -join "`n")
Write-Utf8NoBomLf -Path $StderrPath -Text ($stderrLines -join "`n")

$Meta = [ordered]@{
  schema = "legacy_doctor.tier0.freeze.meta.v1"
  repo_root = $RepoRoot
  run_id = $RunId
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  runner_count = [int]$RunnerList.Count
  runners = @($results)
  parsed_scripts = @($ScriptsToParse)
  hashed_artifacts = @($ArtifactsToHash)
}

Write-Utf8NoBomLf -Path $MetaPath -Text (ToCanonJson $Meta)

$HashTargets = @(
  $StdoutPath,
  $StderrPath,
  $MetaPath
) + $ScriptsToParse + $ArtifactsToHash

# FREEZE_SYNTHETIC_SOURCE_AFTER_RUNNERS_V3
$GeneratedSyntheticSource = Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin"
if(-not (Test-Path -LiteralPath $GeneratedSyntheticSource -PathType Leaf)){
  Die "GENERATED_ARTIFACT_MISSING" $GeneratedSyntheticSource
}

Write-Output ("ARTIFACT_GENERATED_OK: " + $GeneratedSyntheticSource)
$HashTargets = @($HashTargets) + @($GeneratedSyntheticSource)
$HashLines = @()
foreach($f in @($HashTargets | Select-Object -Unique)){
  if(-not (Test-Path -LiteralPath $f -PathType Leaf)){
    Die "FREEZE_HASH_TARGET_MISSING" $f
  }

  $rel = $f.Substring($RepoRoot.Length + 1).Replace("\","/")
  $HashLines += ((HexSha256File $f) + "  " + $rel)
}

Write-Utf8NoBomLf -Path $ShaPath -Text ($HashLines -join "`n")

Write-Output ("FREEZE_RUN_DIR: " + $RunDir)
Write-Output ("FREEZE_META: " + $MetaPath)
Write-Output ("FREEZE_SHA256SUMS: " + $ShaPath)
Write-Output "LEGACY_DOCTOR_TIER0_FREEZE_OK"
