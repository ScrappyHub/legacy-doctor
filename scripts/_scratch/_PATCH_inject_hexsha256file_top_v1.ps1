param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,(Utf8NoBom))
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_verify_imagefile_v1.ps1"

if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){
  Die "MISSING_TARGET" $Target
}

$text = [IO.File]::ReadAllText($Target,(Utf8NoBom))
$text = ($text -replace "`r`n","`n") -replace "`r","`n"

# guard: do not double-insert
if($text.Contains("function HexSha256File(")){
  Write-Output "ALREADY_PRESENT"
  return
}

$inject = @'
function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    throw ("MISSING_FILE:" + $Path)
  }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [IO.File]::OpenRead($Path)
    try {
      $hash = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}
'@

# inject right after Set-StrictMode block (safe anchor)
$anchor = 'Set-StrictMode -Version Latest'
$idx = $text.IndexOf($anchor,[System.StringComparison]::Ordinal)

if($idx -lt 0){
  Die "ANCHOR_NOT_FOUND" $anchor
}

$insertPos = $idx + $anchor.Length
$text2 = $text.Insert($insertPos, "`n`n" + $inject + "`n")

Write-Utf8NoBomLf -Path $Target -Text $text2
Parse-GateFile $Target

Write-Output ("PATCH_OK TARGET=" + $Target)