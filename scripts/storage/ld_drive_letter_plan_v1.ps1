param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;EnsureDir $dir;$t=($Text-replace"`r`n","`n")-replace"`r","`n";if(-not $t.EndsWith("`n")){$t+="`n"};[IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_ld_drive_letter_plan_v1.ps1")
$availability="available";$disks=@();$partitions=@();$volumes=@();$rows=@()
try{
  $disks=@(Get-Disk -ErrorAction Stop|Sort-Object Number)
  $partitions=@(Get-Partition -ErrorAction Stop|Sort-Object DiskNumber,PartitionNumber)
  $volumes=@(Get-Volume -ErrorAction Stop)
}catch{$availability="unavailable"}

$observedUsedLetters=@($volumes|ForEach-Object{LDLTR-NormalizeLetter $_.DriveLetter}|Where-Object{$_}|Sort-Object -Unique)
$planningLetters=@($observedUsedLetters)
$reservedLetters=@("A","B","C")
foreach($partition in @($partitions)){
  $disk=@($disks|Where-Object{[int]$_.Number-eq[int]$partition.DiskNumber}|Select-Object -First 1)
  if($disk.Count-eq 0){continue}
  $volume=$null
  try{$volume=$partition|Get-Volume -ErrorAction Stop|Select-Object -First 1}catch{$volume=$null}
  $diskFacts=[ordered]@{is_offline=[bool]$disk[0].IsOffline;is_boot=[bool]$disk[0].IsBoot;is_system=[bool]$disk[0].IsSystem}
  $partitionFacts=[ordered]@{is_boot=[bool]$partition.IsBoot;is_system=[bool]$partition.IsSystem;is_hidden=[bool]$partition.IsHidden;drive_letter=(LDLTR-NormalizeLetter $partition.DriveLetter);partition_type=[string]$partition.Type;size_bytes=[UInt64]$partition.Size}
  $volumeFacts=$(if($null-ne$volume){[ordered]@{file_system=[string]$volume.FileSystem;drive_type=[string]$volume.DriveType;label=[string]$volume.FileSystemLabel;health=[string]$volume.HealthStatus}}else{$null})
  $blockers=@(LDLTR-EvaluateCandidate -Disk $diskFacts -Partition $partitionFacts -Volume $volumeFacts)
  $suggested=""
  if($blockers.Count-eq 0){$suggested=LDLTR-ChooseLetter -UsedLetters $planningLetters -ReservedLetters $reservedLetters;if([string]::IsNullOrWhiteSpace($suggested)){$blockers=@("NO_FREE_DRIVE_LETTER")}else{$planningLetters+= $suggested}}
  $rows+=,([ordered]@{disk_number=[int]$partition.DiskNumber;partition_number=[int]$partition.PartitionNumber;disk_name=[string]$disk[0].FriendlyName;bus_type=[string]$disk[0].BusType;partition_type=[string]$partition.Type;partition_size_bytes=[UInt64]$partition.Size;current_drive_letter=(LDLTR-NormalizeLetter $partition.DriveLetter);file_system=$(if($null-ne$volume){[string]$volume.FileSystem}else{""});volume_label=$(if($null-ne$volume){[string]$volume.FileSystemLabel}else{""});eligible=($blockers.Count-eq 0);suggested_drive_letter=$suggested;blockers=@($blockers)})
}
$eligible=@($rows|Where-Object{$_.eligible}).Count
$receipt=[ordered]@{schema="ld.device.drive_letter_plan.receipt.v1";event_type="ld.device.drive_letter_plan.receipt.v1";ok=($availability-eq"available");availability=$availability;repo_root=$RepoRoot;mode="read_only_drive_letter_plan";destructive=$false;write_test=$false;assigns_drive_letter=$false;execution_supported=$false;disk_count=[int]$disks.Count;partition_count=[int]$partitions.Count;used_letters=@($observedUsedLetters);reserved_letters=$reservedLetters;eligible_count=[int]$eligible;excluded_count=[int]($rows.Count-$eligible);rows=@($rows);created_utc=[DateTime]::UtcNow.ToString("o")}
$outDir=Join-Path $RepoRoot "proofs\receipts\drive_letter_plan";$outPath=Join-Path $outDir ("drive_letter_plan_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")+".json")
$json=$receipt|ConvertTo-Json -Depth 40 -Compress;Write-Utf8NoBomLf $outPath $json
Write-Output ("DRIVE_LETTER_PLAN_PATH: "+$outPath);Write-Output ("DRIVE_LETTER_PLAN_ELIGIBLE: "+$eligible);Write-Output $json
if($receipt.ok){Write-Output "LD_DRIVE_LETTER_PLAN_OK"}else{Write-Output "LD_DRIVE_LETTER_PLAN_UNAVAILABLE"}
