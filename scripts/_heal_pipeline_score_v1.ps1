param([Parameter(Mandatory=$true)][string]$Scorer)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function WriteUtf8NoBom([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$Text,$enc)
}

if(-not (Test-Path -LiteralPath $Scorer)) { throw ("MISSING_SCORER: " + $Scorer) }

# Backup once (do NOT parse-check anything here)
$bak = ($Scorer + ".bak")
if(-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $Scorer -Destination $bak -Force }

# Read as lines (works even if file has broken quotes)
$lines = Get-Content -LiteralPath $Scorer

# Replace the first Write-Host line that references .detail (this is where mojibake usually explodes)
$idx = -1
for($i=0; $i -lt $lines.Count; $i++){
  $ln = $lines[$i]
  if($ln -match "Write-Host" -and $ln -match "\.detail"){ $idx = $i; break }
}

if($idx -ge 0){
  $dlr = [char]36  # $
  $lines[$idx] = "    Write-Host (`"{0} #{1} {2} - {3}`" -f " + $dlr + "mark, " + $dlr + "c.id, " + $dlr + "c.name, " + $dlr + "c.detail)"
  Write-Host ("HEALED: replaced .detail Write-Host at line index {0} (0-based)" -f $idx) -ForegroundColor Green
} else {
  Write-Host "WARN: did not find a Write-Host line containing .detail (no line replacement applied)" -ForegroundColor Yellow
}

# ASCII scrub entire file (keep TAB/CR/LF + printable ASCII)
$sb = New-Object System.Text.StringBuilder
for($i=0; $i -lt $lines.Count; $i++){
  $ln = $lines[$i]
  foreach($ch in $ln.ToCharArray()){
    $code = [int][char]$ch
    if(($code -eq 9) -or ($code -eq 10) -or ($code -eq 13) -or ($code -ge 32 -and $code -le 126)){
      [void]$sb.Append($ch)
    }
  }
  [void]$sb.Append("`r`n")
}

$raw2 = $sb.ToString()
WriteUtf8NoBom $Scorer $raw2
Write-Host ("HEALED + WROTE UTF8(noBOM): {0}" -f $Scorer) -ForegroundColor Green
Write-Host ("NOTE: now run scorer to confirm parse.") -ForegroundColor Cyan