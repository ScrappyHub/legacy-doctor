param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }
  return [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-GateFile([string]$Path){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }

  Write-Host ("PARSE_OK: " + $Path) -ForegroundColor Green
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Targets = @(
  (Join-Path $RepoRoot "scripts\storage\ld_device_inventory_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_mount_state_v1.ps1")
)

foreach($Target in @($Targets)){
  $text = Read-Utf8 $Target

  if($text -notmatch 'function NormalizeDriveLetter'){
    $insert = @'
function NormalizeDriveLetter([object]$Value){
  if($null -eq $Value){ return "" }

  $s = [string]$Value
  $s = $s.Replace([string][char]0,"").Trim()

  if([string]::IsNullOrWhiteSpace($s)){ return "" }

  return $s
}

'@

    $marker = 'function EnsureDir'
    $idx = $text.IndexOf($marker)
    if($idx -lt 0){
      Die "MARKER_NOT_FOUND" ($Target + ": " + $marker)
    }

    $text = $text.Insert($idx,$insert)
  }

  $text = $text.Replace('[string]$p.DriveLetter', '(NormalizeDriveLetter $p.DriveLetter)')
  $text = $text.Replace('[string]$Partition.DriveLetter', '(NormalizeDriveLetter $Partition.DriveLetter)')

  Write-Utf8NoBomLf -Path $Target -Text $text
  Parse-GateFile $Target
}

Write-Host "PATCH_OK: STORAGE03_NULL_DRIVE_LETTER_NORMALIZED" -ForegroundColor Green