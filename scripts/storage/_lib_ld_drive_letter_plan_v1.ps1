param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDLTR-NormalizeLetter([object]$Value){
  if($null -eq $Value){ return "" }
  return ([string]$Value).Replace([string][char]0,"").Trim().TrimEnd(":").ToUpperInvariant()
}

function LDLTR-EvaluateCandidate([object]$Disk,[object]$Partition,[object]$Volume){
  $blockers = @()
  if($null -eq $Disk){ return @("DISK_FACTS_MISSING") }
  if($null -eq $Partition){ return @("PARTITION_FACTS_MISSING") }
  if([bool]$Disk.is_offline){ $blockers += "DISK_OFFLINE" }
  if([bool]$Disk.is_boot){ $blockers += "BOOT_DISK_EXCLUDED" }
  if([bool]$Disk.is_system){ $blockers += "SYSTEM_DISK_EXCLUDED" }
  if([bool]$Partition.is_boot){ $blockers += "BOOT_PARTITION_EXCLUDED" }
  if([bool]$Partition.is_system){ $blockers += "SYSTEM_PARTITION_EXCLUDED" }
  if([bool]$Partition.is_hidden){ $blockers += "HIDDEN_PARTITION_EXCLUDED" }
  if(-not [string]::IsNullOrWhiteSpace((LDLTR-NormalizeLetter $Partition.drive_letter))){ $blockers += "DRIVE_LETTER_ALREADY_PRESENT" }
  $partitionType = ([string]$Partition.partition_type).Trim()
  if($partitionType -match "(?i)system|reserved|recovery|unknown"){ $blockers += "PROTECTED_PARTITION_TYPE" }
  if([UInt64]$Partition.size_bytes -lt 1048576){ $blockers += "PARTITION_TOO_SMALL" }
  if($null -eq $Volume){
    $blockers += "VOLUME_NOT_RECOGNIZED"
  } else {
    $fileSystem = ([string]$Volume.file_system).Trim()
    if([string]::IsNullOrWhiteSpace($fileSystem) -or $fileSystem -match "(?i)^RAW$"){ $blockers += "FILESYSTEM_UNKNOWN_OR_RAW" }
    $driveType = ([string]$Volume.drive_type).Trim()
    if($driveType -match "(?i)CD-ROM|Optical"){ $blockers += "OPTICAL_VOLUME_EXCLUDED" }
  }
  return @($blockers | Sort-Object -Unique)
}

function LDLTR-ChooseLetter([string[]]$UsedLetters,[string[]]$ReservedLetters = @("A","B","C")){
  $used = @($UsedLetters | ForEach-Object { LDLTR-NormalizeLetter $_ } | Where-Object { $_ } | Sort-Object -Unique)
  $reserved = @($ReservedLetters | ForEach-Object { LDLTR-NormalizeLetter $_ } | Where-Object { $_ } | Sort-Object -Unique)
  foreach($character in "DEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()){
    $candidate = [string]$character
    if(($used -notcontains $candidate) -and ($reserved -notcontains $candidate)){ return $candidate }
  }
  return ""
}

function LDLTR-ExportModuleInfo(){
  return [ordered]@{schema="ld.drive_letter_plan.lib.info.v1";name="_lib_ld_drive_letter_plan_v1.ps1";provides=@("LDLTR-EvaluateCandidate","LDLTR-ChooseLetter")}
}

