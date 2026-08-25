param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDDST-Die([string]$Code,[string]$Detail){ throw ($Code+":"+$Detail) }

function LDDST-FullPath([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ LDDST-Die "PATH_REQUIRED" "" }
  return [IO.Path]::GetFullPath($Path).TrimEnd("\")
}

function LDDST-IsSameOrNested([string]$Candidate,[string]$Root){
  $candidateFull=LDDST-FullPath $Candidate;$rootFull=LDDST-FullPath $Root
  return $candidateFull.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase)-or$candidateFull.StartsWith(($rootFull+"\"),[StringComparison]::OrdinalIgnoreCase)
}

function LDDST-SafeSegment([string]$Value,[string]$Fallback="item"){
  $text=([string]$Value).Trim().ToLowerInvariant()
  $text=[Text.RegularExpressions.Regex]::Replace($text,"[^a-z0-9]+","-").Trim("-")
  if([string]::IsNullOrWhiteSpace($text)){$text=$Fallback}
  if($text.Length-gt 48){$text=$text.Substring(0,48).TrimEnd("-")}
  return $text
}

function LDDST-Layout([string]$Root){
  $rootFull=LDDST-FullPath $Root
  return [ordered]@{
    control=(Join-Path $rootFull ".legacy-doctor")
    file_backups=(Join-Path $rootFull "content\file-backups")
    disk_images=(Join-Path $rootFull "content\disk-images")
    optical_images=(Join-Path $rootFull "content\optical-images")
    device_exports=(Join-Path $rootFull "content\device-exports")
    staging=(Join-Path $rootFull "staging")
    upload_queue=(Join-Path $rootFull "upload-queue")
    receipts=(Join-Path $rootFull "receipts")
    quarantine=(Join-Path $rootFull "quarantine")
    cleared_copies=(Join-Path $rootFull "quarantine\cleared-copies")
  }
}

function LDDST-ProfilePath([string]$Root){return (Join-Path (LDDST-FullPath $Root) ".legacy-doctor\destination-profile.v1.json")}

function LDDST-ProfileId([string]$Root,[string]$Label){
  $identity=(LDDST-FullPath $Root).ToLowerInvariant()+"`n"+([string]$Label).Trim()+"`nld.destination.layout.v1"
  return (LDREC-HexSha256TextLf $identity).Substring(0,24)
}

function LDDST-NewProfile([string]$Root,[string]$Label,[string]$CreatedUtc){
  $layout=LDDST-Layout $Root
  return [ordered]@{
    schema="ld.backup.destination_profile.v1"
    event_type="ld.backup.destination_profile.v1"
    profile_id=(LDDST-ProfileId -Root $Root -Label $Label)
    label=([string]$Label).Trim()
    root_path=(LDDST-FullPath $Root)
    layout_version="ld.destination.layout.v1"
    folder_map=$layout
    source_media_mutable=$false
    clear_policy="quarantine_destination_copies_only"
    upload_policy="verified_artifacts_only"
    created_utc=$CreatedUtc
  }
}

function LDDST-ModeFolder([object]$Profile,[string]$Mode){
  switch($Mode){
    "file_backup"{return [string]$Profile.folder_map.file_backups}
    "disk_image"{return [string]$Profile.folder_map.disk_images}
    "optical_image"{return [string]$Profile.folder_map.optical_images}
    "device_export"{return [string]$Profile.folder_map.device_exports}
    default{LDDST-Die "BACKUP_MODE_INVALID" $Mode}
  }
}

function LDDST-ExportModuleInfo(){return [ordered]@{schema="ld.destination_profile.lib.info.v1";name="_lib_ld_destination_profile_v1.ps1";provides=@("LDDST-FullPath","LDDST-IsSameOrNested","LDDST-SafeSegment","LDDST-Layout","LDDST-ProfilePath","LDDST-ProfileId","LDDST-NewProfile","LDDST-ModeFolder")}}
