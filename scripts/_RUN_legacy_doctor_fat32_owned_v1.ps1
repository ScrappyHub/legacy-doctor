param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function RUN-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function RUN-Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }

function RUN-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function RUN-WriteUtf8NoBomLf([string]$path,[string]$text){
  $dir = Split-Path -Parent $path
  if($dir){ RUN-EnsureDir $dir }
  $t = ($text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($path,$t,(RUN-Utf8NoBom))
}

function RUN-AppendUtf8NoBomLf([string]$path,[string]$line){
  $dir = Split-Path -Parent $path
  if($dir){ RUN-EnsureDir $dir }
  $t = ($line -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($path,$t,(RUN-Utf8NoBom))
}

function RUN-ParseGate([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    RUN-Die "PARSE_GATE_MISSING" $Path
  }
  $tok=$null
  $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    RUN-Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }
}

function RUN-Sha256HexTextLf([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes(($Text + "`n"))
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }
  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.AppendFormat("{0:x2}", $b)
  }
  return $sb.ToString()
}

function RUN-Canon($v){
  if($null -eq $v){ return $null }

  if($v -is [string] -or $v -is [int] -or $v -is [long] -or $v -is [uint16] -or $v -is [uint32] -or $v -is [uint64] -or $v -is [double] -or $v -is [decimal] -or $v -is [bool]){
    return $v
  }

  if($v -is [datetime]){
    return $v.ToUniversalTime().ToString("o")
  }

  if($v -is [System.Collections.IDictionary]){
    $keys = @($v.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $o = [ordered]@{}
    foreach($k in $keys){
      $o[$k] = RUN-Canon $v[$k]
    }
    return $o
  }

  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $a = @()
    foreach($x in $v){
      $a += ,(RUN-Canon $x)
    }
    return $a
  }

  return ([string]$v)
}

function RUN-ToCanonJson($v){
  return ((RUN-Canon $v) | ConvertTo-Json -Depth 50 -Compress)
}

function RUN-ReceiptPath([string]$RepoRoot){
  return (Join-Path $RepoRoot "proofs\receipts\storage.ndjson")
}

function RUN-EmitReceipt([string]$RepoRoot,[hashtable]$Obj){
  $rp = RUN-ReceiptPath $RepoRoot
  $json = RUN-ToCanonJson $Obj
  $rh = RUN-Sha256HexTextLf $json

  $o2 = [ordered]@{}
  foreach($k in $Obj.Keys){ $o2[$k] = $Obj[$k] }
  $o2["receipt_hash"] = $rh

  RUN-AppendUtf8NoBomLf $rp (RUN-ToCanonJson $o2)
  return $rh
}

function RUN-RunPsFile([string]$PSExe,[string]$ScriptPath,[string[]]$Argv){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    RUN-Die "RUN_MISSING" $ScriptPath
  }

  $allArgs = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$ScriptPath
  ) + $Argv

  $out = & $PSExe @allArgs 2>&1
  $exitCode = $LASTEXITCODE

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output   = @(@($out) | ForEach-Object { [string]$_ })
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe    = (Get-Command powershell.exe -ErrorAction Stop).Source

$StorageDir  = Join-Path $RepoRoot "scripts\storage"
$SelftestDir = Join-Path $RepoRoot "scripts\selftest"
$ProofDir    = Join-Path $RepoRoot "proofs\transcripts\ld_fat32_owned_v1"

RUN-EnsureDir $ProofDir

$LibRaw     = Join-Path $StorageDir "_lib_ld_rawdisk_v1.ps1"
$LibLayout  = Join-Path $StorageDir "_lib_ld_fat32_layout_v1.ps1"
$Verify     = Join-Path $StorageDir "ld_verify_fat32_layout_v1.ps1"
$Plan       = Join-Path $StorageDir "ld_plan_format_fat32_owned_v1.ps1"
$Format     = Join-Path $StorageDir "ld_format_fat32_owned_v1.ps1"
$Selftest   = Join-Path $SelftestDir "_selftest_ld_fat32_owned_v1.ps1"

$Targets = @(
  $LibRaw,
  $LibLayout,
  $Verify,
  $Plan,
  $Format,
  $Selftest
)

# ------------------------------------------------------------
# 1) Parse-gate all relevant files
# ------------------------------------------------------------
foreach($t in $Targets){
  RUN-ParseGate $t
  Write-Host ("PARSE_OK: " + $t) -ForegroundColor DarkGray
}

# ------------------------------------------------------------
# 2) Run selftest
# ------------------------------------------------------------
$run = RUN-RunPsFile -PSExe $PSExe -ScriptPath $Selftest -Argv @("-RepoRoot",$RepoRoot)

$stdoutPath = Join-Path $ProofDir "selftest_stdout.log"
$statusPath = Join-Path $ProofDir "selftest_status.json"

$stdoutText = ""
if(@($run.Output).Count -gt 0){
  $stdoutText = (@($run.Output) -join "`n")
}

RUN-WriteUtf8NoBomLf $stdoutPath $stdoutText

foreach($line in @($run.Output)){
  [Console]::Out.WriteLine($line)
}

if($run.ExitCode -ne 0){
  RUN-Die "SELFTEST_EXIT_NONZERO" ([string]$run.ExitCode)
}

$joined = @(@($run.Output)) -join "`n"
if($joined -notmatch "FULL_GREEN"){
  RUN-Die "SELFTEST_MISSING_FULL_GREEN" "selftest did not emit FULL_GREEN"
}

# ------------------------------------------------------------
# 3) Emit deterministic status artifact
# ------------------------------------------------------------
$status = [ordered]@{
  schema = "ld.fat32.owned.runner.status.v1"
  time_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  selftest_script = $Selftest
  selftest_exit_code = $run.ExitCode
  selftest_stdout_sha256 = RUN-Sha256HexTextLf $stdoutText
  token = "LEGACY_DOCTOR_FAT32_OWNED_ALL_GREEN"
  ok = $true
}

$statusJson = RUN-ToCanonJson $status
RUN-WriteUtf8NoBomLf $statusPath $statusJson

# ------------------------------------------------------------
# 4) Emit runner receipt
# ------------------------------------------------------------
$receipt = [ordered]@{
  schema = "storage.receipt.v1"
  action = "run-fat32-owned-tier0"
  time_utc = [DateTime]::UtcNow.ToString("o")
  host = $env:COMPUTERNAME
  token = "LEGACY_DOCTOR_FAT32_OWNED_ALL_GREEN"
  ok = $true
  selftest_script = $Selftest
  selftest_stdout_sha256 = RUN-Sha256HexTextLf $stdoutText
  status_sha256 = RUN-Sha256HexTextLf $statusJson
}

[void](RUN-EmitReceipt -RepoRoot $RepoRoot -Obj $receipt)

# ------------------------------------------------------------
# 5) Final token
# ------------------------------------------------------------
Write-Host "LEGACY_DOCTOR_FAT32_OWNED_ALL_GREEN" -ForegroundColor Green
exit 0
