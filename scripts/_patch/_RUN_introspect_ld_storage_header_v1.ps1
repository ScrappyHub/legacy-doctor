param([Parameter(Mandatory=$true)][string]$ToolPath,[Parameter(Mandatory=$true)][string]$OutPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if(-not (Test-Path -LiteralPath $ToolPath)){ throw ('MISSING_TOOL: ' + $ToolPath) }
$raw = Get-Content -Raw -LiteralPath $ToolPath -Encoding UTF8
$txt = ($raw -replace "`r`n","`n") -replace "`r","`n"
$lines = $txt.Split("`n")

# Heuristic: include the first param(...) block if present, plus top-of-file header (first 200 lines max).
$maxHead = [Math]::Min(200, $lines.Length)
$head = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $maxHead;$i++){ [void]$head.Add($lines[$i]) }

# Additionally try to capture a Cmd parameter region by searching for 'Cmd' inside the first 400 lines.
$scanMax = [Math]::Min(400, $lines.Length)
$cmdHit = -1
for($i=0;$i -lt $scanMax;$i++){ if($lines[$i] -match '(?i)\bCmd\b'){ $cmdHit = $i; break } }
$tail = New-Object System.Collections.Generic.List[string]
if($cmdHit -ge 0){
  $start = [Math]::Max(0, $cmdHit - 25)
  $end   = [Math]::Min($lines.Length-1, $cmdHit + 60)
  for($j=$start;$j -le $end;$j++){ [void]$tail.Add($lines[$j]) }
}

$out = New-Object System.Collections.Generic.List[string]
[void]$out.Add('=== BEGIN: HEADER+TOP (<=200 lines) ===')
foreach($ln in @($head.ToArray())){ [void]$out.Add($ln) }
[void]$out.Add('=== END: HEADER+TOP ===')
[void]$out.Add('')
if($cmdHit -ge 0){
  [void]$out.Add('=== BEGIN: CMD REGION (context) ===')
  foreach($ln in @($tail.ToArray())){ [void]$out.Add($ln) }
  [void]$out.Add('=== END: CMD REGION ===')
} else {
  [void]$out.Add('=== CMD REGION: NOT FOUND IN FIRST 400 LINES ===')
}

$final = ($out.ToArray() -join "`n") + "`n"
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($OutPath, $final, $enc)
Write-Host ('INTROSPECT_OK: ' + $OutPath) -ForegroundColor Green
