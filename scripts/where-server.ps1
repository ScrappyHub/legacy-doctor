param(
  [int]$Port = 8787
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-ListeningPid([int]$p) {
  $lines = & netstat.exe -ano -p TCP | Select-String -Pattern "LISTENING" | ForEach-Object { $_.Line }
  foreach ($ln in $lines) {
    $parts = ($ln -replace "\s+", " ").Trim().Split(" ")
    if ($parts.Count -lt 5) { continue }

    $local = $parts[1]
    $state = $parts[3]
    $listenPid = $parts[4]

    if ($state -ne "LISTENING") { continue }
    if ($local -match (":$p$")) { return [int]$listenPid }
  }
  return $null
}

$listenPid = Get-ListeningPid $Port
if (-not $listenPid) { throw "No LISTENING process found on TCP port $Port" }

$proc = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $listenPid)

Write-Host ("LISTENING  port={0}  pid={1}  name={2}" -f $Port, $listenPid, $proc.Name) -ForegroundColor Green
if ($proc.ExecutablePath) { Write-Host ("EXE : {0}" -f $proc.ExecutablePath) -ForegroundColor DarkGray }
if ($proc.CommandLine)    { Write-Host ("CMD : {0}" -f $proc.CommandLine)    -ForegroundColor DarkGray }

# Parent chain (best-effort)
$ppid = $proc.ParentProcessId
if ($ppid) {
  $parent = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $ppid) -ErrorAction SilentlyContinue
  if ($parent) {
    Write-Host ("PARENT  pid={0}  name={1}" -f $ppid, $parent.Name) -ForegroundColor DarkGray
    if ($parent.CommandLine) { Write-Host ("PARENT_CMD : {0}" -f $parent.CommandLine) -ForegroundColor DarkGray }
  }
}
