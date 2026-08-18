param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$Code,[string]$Detail){throw($Code+":"+$Detail)}
function Require([bool]$Condition,[string]$Code,[string]$Detail){if(-not$Condition){Die $Code $Detail}}
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_verified_image_v1.ps1")
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_optical_v1.ps1")
$root=Join-Path $RepoRoot "proofs\selftest\optical_image";if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force};EnsureDir $root
$source=Join-Path $root "fixture-disc.bin";$temporary=Join-Path $root "fixture-disc.iso.partial"
$sectorCount=128;$bytes=New-Object byte[] ($sectorCount*2048);for($i=0;$i-lt$bytes.Length;$i++){$bytes[$i]=[byte](($i*13+29)%256)};[IO.File]::WriteAllBytes($source,$bytes)
$stream=[IO.File]::OpenRead($source);try{$result=LDIMG-CopyStreamVerified -SourceStream $stream -TemporaryPath $temporary -ExpectedBytes ([UInt64]$bytes.Length) -BufferBytes 4096}finally{$stream.Dispose()}
Require ([bool]$result.source_stable) "OPTICAL_FIXTURE_SOURCE_UNSTABLE" ""
Require ([bool]$result.destination_matches) "OPTICAL_FIXTURE_HASH_MISMATCH" ""
Require (([string]$result.source_sha256)-ceq(LDREC-HexSha256File $temporary)) "OPTICAL_FIXTURE_INDEPENDENT_HASH_BAD" ""
$fixtureSerialHash="a"*64
$readyFacts=[ordered]@{media_loaded=$true;device_name="Fixture DVD Drive";size_bytes=[UInt64]$bytes.Length;volume_serial_sha256=$fixtureSerialHash}
$ready=@(LDOPT-EvaluateMedia -Facts $readyFacts -ExpectedDeviceName "Fixture DVD Drive" -ExpectedBytes ([UInt64]$bytes.Length) -ExpectedVolumeSerialSha256 $fixtureSerialHash -MaxBytes ([UInt64]$bytes.Length) -DestinationFreeBytes 1048576)
Require ($ready.Count-eq 0) "READY_DISC_BLOCKED" ($ready-join",")
$empty=@(LDOPT-EvaluateMedia -Facts ([ordered]@{media_loaded=$false}) -ExpectedDeviceName "" -ExpectedBytes 0 -ExpectedVolumeSerialSha256 "" -MaxBytes 0 -DestinationFreeBytes 1048576)
Require ($empty.Count-eq 1-and$empty[0]-eq"NO_MEDIA") "NO_MEDIA_NOT_EXPLICIT" ($empty-join",")
$wrong=@(LDOPT-EvaluateMedia -Facts $readyFacts -ExpectedDeviceName "Other Drive" -ExpectedBytes ([UInt64]$bytes.Length) -ExpectedVolumeSerialSha256 ("b"*64) -MaxBytes 1 -DestinationFreeBytes 1)
Require ($wrong-contains"OPTICAL_DEVICE_NAME_MISMATCH") "DEVICE_PIN_GATE_MISSING" ""
Require ($wrong-contains"VOLUME_SERIAL_MISMATCH") "SERIAL_PIN_GATE_MISSING" ""
Require ($wrong-contains"EXACT_MEDIA_BOUND_REQUIRED") "SIZE_BOUND_GATE_MISSING" ""
Require ($wrong-contains"DESTINATION_SPACE_INSUFFICIENT") "SPACE_GATE_MISSING" ""
Write-Output "PASS: deterministic 2048-byte-sector optical fixture copied and independently hashed"
Write-Output "PASS: no media is explicit and device, serial, size, and free-space gates fail closed"
Write-Output "SELFTEST_LD_OPTICAL_IMAGE_OK"
