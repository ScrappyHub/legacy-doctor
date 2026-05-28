param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die($c,$d){ throw ($c+":"+$d) }

$RepoRoot = (Resolve-Path $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_tier0_full_green_v1.ps1"

if(-not (Test-Path $Target)){
  Die "TARGET_MISSING" $Target
}

$text = Get-Content -Raw -LiteralPath $Target -Encoding UTF8

# Replace ANY receipt/JSON construction with safe block
$pattern = '(\$receipt\s*=.*?ConvertTo-Json.*?\))'

$newBlock = @'
# SAFE RECEIPT BUILD (PS5.1)
$receiptObj = New-Object PSObject

Add-Member -InputObject $receiptObj -NotePropertyName "run_id" -NotePropertyValue $RunId
Add-Member -InputObject $receiptObj -NotePropertyName "utc" -NotePropertyValue $UtcNow

# build results array safely
$resList = New-Object System.Collections.ArrayList
foreach($r in $ResultRows){
  $o = New-Object PSObject
  Add-Member -InputObject $o -NotePropertyName "runner" -NotePropertyValue $r.runner
  Add-Member -InputObject $o -NotePropertyName "ok" -NotePropertyValue $r.ok
  [void]$resList.Add($o)
}

Add-Member -InputObject $receiptObj -NotePropertyName "results" -NotePropertyValue $resList

$receiptJson = $receiptObj | ConvertTo-Json -Depth 10 -Compress
'@

# aggressive replace fallback if pattern fails
if($text -match $pattern){
  $text = [regex]::Replace($text,$pattern,$newBlock)
} else {
  # fallback: append safe block at end
  $text = $text + "`n" + $newBlock
}

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Target,$text,$enc)

# parse gate
$null = [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Target -Encoding UTF8))

Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green