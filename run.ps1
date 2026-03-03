param([switch]$AutoPort)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$py   = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) { throw "Missing venv python: $py" }

$port = 8787
$env:PYTHONPATH = "$root\src"
cd $root
& $py -m uvicorn legacy_doctor.api.server:app --host 127.0.0.1 --port $port
