param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$TimeoutSeconds = 90,
  [string]$TestPattern = "*.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function EnsureDir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if($TimeoutSeconds -lt 5){ Die "BAD_TIMEOUT" ([string]$TimeoutSeconds) }

$runId = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$runDir = Join-Path $RepoRoot ("proofs\verification\" + $runId)
EnsureDir $runDir

$parseFiles = @()
$parseFiles += @(Get-ChildItem (Join-Path $RepoRoot "scripts\storage") -File -Filter *.ps1)
$parseFiles += @(Get-ChildItem (Join-Path $RepoRoot "scripts\media") -File -Filter *.ps1)
$parseFiles += @(Get-ChildItem (Join-Path $RepoRoot "scripts\selftest") -File -Filter *.ps1)
$parseFiles += @(Get-ChildItem (Join-Path $RepoRoot "scripts") -File -Filter _RUN_*.ps1)
$parseFiles += @(Get-ChildItem (Join-Path $RepoRoot "scripts\test") -File -Filter *.ps1)

$parseErrors = @()
foreach($file in @($parseFiles | Sort-Object FullName -Unique)){
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  foreach($e in @($errors)){
    $parseErrors += ($file.FullName + ":" + $e.Extent.StartLineNumber + ":" + $e.Message)
  }
}
if(@($parseErrors).Count -gt 0){ Die "POWERSHELL_PARSE_FAILED" ($parseErrors -join " | ") }

$legacyReceiptParsers = @(
  Get-ChildItem (Join-Path $RepoRoot "scripts\storage") -File -Filter *.ps1 |
    Where-Object { $_.Name -ne "_lib_ld_receipts_v1.ps1" } |
    Select-String -Pattern "First-JsonObjectFromOutput|JSON_SCHEMA_OUTPUT_MISSING"
)
if($legacyReceiptParsers.Count -gt 0){
  Die "LEGACY_RECEIPT_PARSER_PRESENT" (($legacyReceiptParsers | ForEach-Object { $_.Path + ":" + $_.LineNumber }) -join " | ")
}

$workflowPath = Join-Path $RepoRoot ".github\workflows\verify.yml"
if(-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)){ Die "CI_WORKFLOW_MISSING" $workflowPath }

$governancePaths = @(
  (Join-Path $RepoRoot ".gitattributes"),
  (Join-Path $RepoRoot "AGENTS.md"),
  (Join-Path $RepoRoot "CLAUDE.md"),
  (Join-Path $RepoRoot "docs\canonical\ECOSYSTEM_INTEGRATION.md"),
  (Join-Path $RepoRoot "project.contract.json")
)
foreach($governancePath in $governancePaths){
  if(-not (Test-Path -LiteralPath $governancePath -PathType Leaf)){
    Die "GOVERNANCE_FILE_MISSING" $governancePath
  }

  $governanceBytes = [IO.File]::ReadAllBytes($governancePath)
  if($governanceBytes.Length -ge 3 -and $governanceBytes[0] -eq 239 -and $governanceBytes[1] -eq 187 -and $governanceBytes[2] -eq 191){
    Die "GOVERNANCE_FILE_UTF8_BOM_FORBIDDEN" $governancePath
  }
  if(@($governanceBytes | Where-Object { $_ -eq 13 }).Count -gt 0){
    Die "GOVERNANCE_FILE_CRLF_FORBIDDEN" $governancePath
  }
}

try {
  $projectContract = Get-Content -LiteralPath (Join-Path $RepoRoot "project.contract.json") -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
  Die "PROJECT_CONTRACT_JSON_INVALID" $_.Exception.Message
}
if(([string]$projectContract.project_id) -cne "legacy-doctor"){ Die "PROJECT_CONTRACT_ID_MISMATCH" ([string]$projectContract.project_id) }
if(([string]$projectContract.ecosystem.service_id) -cne "legacy-doctor"){ Die "PROJECT_CONTRACT_SERVICE_ID_MISMATCH" ([string]$projectContract.ecosystem.service_id) }
if(([string]$projectContract.ecosystem.layer) -cne "unclassified"){ Die "PROJECT_CONTRACT_UNAPPROVED_LAYER" ([string]$projectContract.ecosystem.layer) }

$integrationText = Get-Content -LiteralPath (Join-Path $RepoRoot "docs\canonical\ECOSYSTEM_INTEGRATION.md") -Raw
if(-not $integrationText.Contains("| Service ID | ``legacy-doctor`` |")){ Die "CANONICAL_INTEGRATION_SERVICE_ID_MISSING" "legacy-doctor" }
if(-not $integrationText.Contains("| Ecosystem layer | ``unclassified`` |")){ Die "CANONICAL_INTEGRATION_LAYER_MISMATCH" "unclassified" }

$rejectedLegacyPaths = @(
  (Join-Path $RepoRoot "lib\doctor-common.ps1"),
  (Join-Path $RepoRoot "scripts\_ld_rescore_and_stage_docs_v1.ps1")
)
foreach($rejectedLegacyPath in $rejectedLegacyPaths){
  if(Test-Path -LiteralPath $rejectedLegacyPath){
    Die "REJECTED_LEGACY_FILE_IN_ACTIVE_TREE" $rejectedLegacyPath
  }
}

$schemaFiles = @(Get-ChildItem (Join-Path $RepoRoot "schemas") -File -Filter *.json | Sort-Object Name)
foreach($schemaFile in $schemaFiles){
  try {
    $schema = Get-Content -LiteralPath $schemaFile.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Die "SCHEMA_JSON_INVALID" ($schemaFile.FullName + ":" + $_.Exception.Message)
  }
  if([string]::IsNullOrWhiteSpace([string]$schema.'$schema')){ Die "SCHEMA_DIALECT_MISSING" $schemaFile.FullName }
  if([string]$schema.type -ne "object"){ Die "SCHEMA_ROOT_NOT_OBJECT" $schemaFile.FullName }
  if($schema.additionalProperties -ne $false){ Die "SCHEMA_ROOT_NOT_CLOSED" $schemaFile.FullName }
  if(@($schema.required).Count -eq 0){ Die "SCHEMA_REQUIRED_MISSING" $schemaFile.FullName }
  foreach($requiredName in @($schema.required)){
    if($null -eq $schema.properties.PSObject.Properties[[string]$requiredName]){
      Die "SCHEMA_REQUIRED_PROPERTY_UNDECLARED" ($schemaFile.FullName + ":" + [string]$requiredName)
    }
  }
}

$tests = @(Get-ChildItem (Join-Path $RepoRoot "scripts\selftest") -File -Filter $TestPattern | Sort-Object Name)
if($tests.Count -eq 0){ Die "NO_TESTS_SELECTED" $TestPattern }
$results = @()
$index = 0

foreach($test in $tests){
  $index++
  $stdoutPath = Join-Path $runDir ("test_" + $index.ToString("00") + ".stdout.txt")
  $stderrPath = Join-Path $runDir ("test_" + $index.ToString("00") + ".stderr.txt")
  $quotedTest = '"' + $test.FullName + '"'
  $quotedRoot = '"' + $RepoRoot + '"'
  $arguments = @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$quotedTest,"-RepoRoot",$quotedRoot)

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = "powershell.exe"
  $startInfo.Arguments = ($arguments -join " ")
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if(-not $process.Start()){ Die "TEST_PROCESS_START_FAILED" $test.FullName }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $completed = $process.WaitForExit($TimeoutSeconds * 1000)
  $timedOut = -not $completed
  if($timedOut){
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    $process.WaitForExit()
  } else {
    $process.WaitForExit()
  }

  $exitCode = $(if($timedOut){ -1 } else { $process.ExitCode })
  $stdout = [string]$stdoutTask.Result
  $stderr = [string]$stderrTask.Result
  [IO.File]::WriteAllText($stdoutPath,$stdout,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($stderrPath,$stderr,[Text.UTF8Encoding]::new($false))
  $process.Dispose()
  $passed = ((-not $timedOut) -and $exitCode -eq 0)

  $results += ,([ordered]@{
    test = $test.Name
    passed = [bool]$passed
    timed_out = [bool]$timedOut
    exit_code = [int]$exitCode
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    error = $(if($passed){ "" } else { (($stderr + "`n" + $stdout).Trim()) })
  })

  $statusText = $(if($passed){ "PASS " } else { "FAIL " })
  Write-Output ($statusText + $test.Name + " exit=" + $exitCode + " timeout=" + $timedOut)
}

$failed = @($results | Where-Object { -not $_.passed })
$summary = [ordered]@{
  schema = "ld.project.verification.summary.v1"
  ok = (@($failed).Count -eq 0)
  destructive = $false
  formatter_quarantine_tested = (@($results | Where-Object { $_.test -eq "_selftest_ld_fat32_owned_writepath_v1.ps1" -and $_.passed }).Count -eq 1)
  powershell_file_count = [int]$parseFiles.Count
  schema_file_count = [int]$schemaFiles.Count
  governance_file_count = [int]$governancePaths.Count
  test_count = [int]$results.Count
  passed_count = [int]($results.Count - $failed.Count)
  failed_count = [int]$failed.Count
  results = @($results)
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$summaryPath = Join-Path $runDir "summary.json"
$summaryJson = $summary | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($summaryPath,($summaryJson.Replace("`r`n","`n") + "`n"),[Text.UTF8Encoding]::new($false))

Write-Output ("VERIFICATION_SUMMARY: " + $summaryPath)
Write-Output ("VERIFICATION_TESTS: " + $summary.passed_count + "/" + $summary.test_count)

if($TestPattern -eq "*.ps1" -and -not $summary.formatter_quarantine_tested){ Die "FORMATTER_QUARANTINE_NOT_PROVEN" $summaryPath }
if(-not $summary.ok){ Die "PROJECT_VERIFICATION_FAILED" $summaryPath }

Write-Output "LEGACY_DOCTOR_PROJECT_VERIFICATION_OK"
