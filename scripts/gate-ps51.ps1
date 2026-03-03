param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Fail([string]$msg) {
  Write-Host $msg -ForegroundColor Red
  exit 1
}

# Targets to scan
$targets = @(
  (Join-Path $RepoRoot "scripts"),
  (Join-Path $RepoRoot "lib")
)

# Exclusions
$excludeExact = @(
  (Join-Path $RepoRoot "scripts\gate-ps51.ps1")
)

$excludePrefixes = @(
  (Join-Path $RepoRoot ".git\"),
  (Join-Path $RepoRoot "vendor\"),
  (Join-Path $RepoRoot "node_modules\")
)

function Is-Excluded([string]$full) {
  foreach ($x in $excludeExact) { if ($full -ieq $x) { return $true } }
  foreach ($p in $excludePrefixes) {
    if ($full.Length -ge $p.Length -and $full.Substring(0, $p.Length) -ieq $p) { return $true }
  }
  return $false
}

# AST/token scan to avoid matching comments/strings
function Scan-File([string]$path) {
  $tokens = $null
  $errors = $null

  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)

  if ($errors -and $errors.Count -gt 0) {
    $msg = ($errors | Select-Object -First 5 | ForEach-Object { $_.Message }) -join "; "
    Fail ("PS5.1 GATE FAILED: PARSE_ERROR`r`n---`r`n{0}`r`n---" -f $msg)
  }

  foreach ($t in $tokens) {
    # Only inspect real code tokens (ignore comments/newlines)
    if ($t.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) { continue }
    if ($t.Kind -eq [System.Management.Automation.Language.TokenKind]::NewLine) { continue }

    # Null-coalescing operators (PS7+): ?? and ??=
    if ($t.Text -eq '??' -or $t.Text -eq '??=') {
      Fail ("PS5.1 GATE FAILED: NULL_COALESCE_OPERATOR`r`n---`r`n{0}:{1}:{2}: {3}`r`n---" -f $path, $t.Extent.StartLineNumber, $t.Extent.StartColumnNumber, $t.Text)
    }

    # Null-conditional (PS7+): ?.  (tokenization may vary; catch by text)
    if ($t.Text -eq '?.') {
      Fail ("PS5.1 GATE FAILED: NULL_CONDITIONAL_OPERATOR`r`n---`r`n{0}:{1}:{2}: {3}`r`n---" -f $path, $t.Extent.StartLineNumber, $t.Extent.StartColumnNumber, $t.Text)
    }
  }

  # Also block ForEach-Object -Parallel (PS7+), but avoid strings/comments:
  $asts = $null
  $tok2 = $null
  $err2 = $null
  $asts = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tok2, [ref]$err2)

  $cmdAsts = $asts.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
  foreach ($c in $cmdAsts) {
    if ($c.GetCommandName() -eq "ForEach-Object") {
      foreach ($el in $c.CommandElements) {
        if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -eq "Parallel") {
          Fail ("PS5.1 GATE FAILED: FOREACH_PARALLEL`r`n---`r`n{0}:{1}:{2}: ForEach-Object -Parallel`r`n---" -f $path, $el.Extent.StartLineNumber, $el.Extent.StartColumnNumber)
        }
      }
    }
  }
}

$files = New-Object System.Collections.Generic.List[string]
foreach ($t in $targets) {
  if (Test-Path -LiteralPath $t) {
    Get-ChildItem -LiteralPath $t -Recurse -File -Filter *.ps1 | ForEach-Object {
      if (-not (Is-Excluded $_.FullName)) { $files.Add($_.FullName) }
    }
  }
}

if ($files.Count -eq 0) {
  Write-Host "PS5.1 GATE: no files found to scan." -ForegroundColor Yellow
  exit 0
}

foreach ($f in $files) {
  Scan-File -path $f
}

Write-Host ("PS5.1 GATE OK: scanned {0} file(s)." -f $files.Count) -ForegroundColor Green
