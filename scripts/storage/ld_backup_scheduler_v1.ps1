param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$StateRoot,
  [ValidateSet("plan","run")][string]$Action="plan",
  [string]$NowUtc="",
  [string]$ConnectedSourceRoot="",
  [switch]$IncludeManual,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_ld_receipts_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_backend_state_v1.ps1")
$StateRoot=LDBS-FullPath $StateRoot
$layout=LDBS-Layout $StateRoot
$blockers=@();$rows=@();$writes=$false;$status="planned"
if([string]::IsNullOrWhiteSpace($NowUtc)){$now=[DateTimeOffset]::UtcNow}else{try{$now=[DateTimeOffset]::Parse($NowUtc)}catch{$blockers+=,"NOW_UTC_INVALID";$now=[DateTimeOffset]::UtcNow}}
$connected=""
if(-not [string]::IsNullOrWhiteSpace($ConnectedSourceRoot)){
  if(Test-Path -LiteralPath $ConnectedSourceRoot -PathType Container){$connected=(Resolve-Path -LiteralPath $ConnectedSourceRoot).Path}else{$blockers+=,"CONNECTED_SOURCE_ROOT_MISSING"}
}

function Get-LatestRun([string]$JobId){
  $runDir=Join-Path $layout.runs $JobId
  if(-not(Test-Path -LiteralPath $runDir -PathType Container)){return $null}
  $last=Get-ChildItem -LiteralPath $runDir -File -Filter *.json|Sort-Object Name|Select-Object -Last 1
  if($null -eq $last){return $null}
  $run=LDBS-ReadJson $last.FullName
  LDBS-AssertSchema $run "ld.backup.job_run.v1" $RepoRoot
  return [ordered]@{path=$last.FullName;value=$run;created=[DateTimeOffset]::Parse([string]$run.created_utc)}
}

if(Test-Path -LiteralPath $layout.jobs -PathType Container){
  foreach($jobFile in @(Get-ChildItem -LiteralPath $layout.jobs -File -Filter *.json|Sort-Object Name)){
    try{
      $job=LDBS-ReadJson $jobFile.FullName
      LDBS-AssertSchema $job "ld.backup.job_spec.v1" $RepoRoot
      $expectedJobId=(LDREC-HexSha256TextLf (([string]$job.source_root).ToLowerInvariant()+"`n"+[string]$job.workspace_manifest_sha256+"`n"+[string]$job.schedule+"`n"+[string]$job.max_files+"`n"+[string]$job.max_bytes)).Substring(0,24)
      if($expectedJobId-cne[string]$job.job_id){throw "JOB_SPEC_IDENTITY_MISMATCH"}
      $workspace=LDBS-Workspace ([string]$job.workspace_manifest_path) $RepoRoot
      if([string]$workspace.sha256-cne[string]$job.workspace_manifest_sha256){throw "WORKSPACE_MANIFEST_HASH_MISMATCH"}
      if([string]$workspace.value.payload_path-cne[string]$job.destination_payload_path){throw "JOB_DESTINATION_MISMATCH"}
      $latest=Get-LatestRun ([string]$job.job_id)
      $eligible=$false;$reason="waiting"
      switch([string]$job.schedule){
        "manual" {if($IncludeManual){$eligible=$true;$reason="manual_requested"}else{$reason="manual_excluded"}}
        "on_connect" {if([string]::IsNullOrWhiteSpace($connected)){$reason="waiting_for_connection"}elseif(([IO.Path]::GetFullPath([string]$job.source_root)).Equals($connected,[StringComparison]::OrdinalIgnoreCase)-and$null -eq $latest){$eligible=$true;$reason="connected_not_run"}elseif($null -ne $latest){$reason="already_run_for_connection"}else{$reason="connected_source_mismatch"}}
        "daily" {if($null -eq $latest){$eligible=$true;$reason="never_run"}elseif(($now-$latest.created).TotalHours -ge 24){$eligible=$true;$reason="daily_interval_elapsed"}else{$reason="daily_interval_not_elapsed"}}
      }
      $runStatus="not_requested";$runPath="";$runHash=""
      if($Action-eq"run"-and$eligible){
        if(-not$Execute){$runStatus="dry_run_ready";$status="dry_run_ready"}
        else{
          $jobRunner=Join-Path $PSScriptRoot "ld_backup_job_v1.ps1"
          $childArgs=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$jobRunner,"-RepoRoot",$RepoRoot,"-StateRoot",$StateRoot,"-Action","run","-JobId",[string]$job.job_id,"-Execute")
          $childOut=& powershell.exe @childArgs
          if($LASTEXITCODE-ne0){throw("JOB_RUNNER_EXIT_NONZERO:"+$LASTEXITCODE)}
          $child=LDREC-ReadReceiptFromOutput $childOut "ld.backup.job.receipt.v1" (Join-Path $RepoRoot "schemas")
          if(-not[bool]$child.ok){throw("JOB_RUNNER_BLOCKED:"+[string]$child.execution_status)}
          $runStatus="succeeded";$runPath=[string]$child.child_receipt_path
          if(Test-Path -LiteralPath $runPath -PathType Leaf){$runHash=LDREC-HexSha256File $runPath}
          $writes=$true;$status="executed"
        }
      }
      $rows+=,[ordered]@{job_id=[string]$job.job_id;job_type=[string]$job.job_type;schedule=[string]$job.schedule;source_root=[string]$job.source_root;eligible=[bool]$eligible;eligibility_reason=$reason;last_run_utc=$(if($null -eq $latest){""}else{[string]$latest.value.created_utc});run_status=$runStatus;run_receipt_path=$runPath;run_receipt_sha256=$runHash}
    }catch{$blockers+=,[string]$_.Exception.Message;$rows+=,[ordered]@{job_id=$jobFile.BaseName;job_type="";schedule="";source_root="";eligible=$false;eligibility_reason="invalid_job";last_run_utc="";run_status="blocked";run_receipt_path="";run_receipt_sha256=""}}
  }
}
if($Action-eq"run"-and-not$Execute-and$blockers.Count-eq0-and$status-eq"planned"){$status="dry_run_ready"}
$ok=($blockers.Count-eq0)
$receipt=[ordered]@{schema="ld.backup.scheduler.receipt.v1";event_type="ld.backup.scheduler.receipt.v1";ok=[bool]$ok;availability=$(if($ok){"available"}else{"blocked"});repo_root=$RepoRoot;state_root=$StateRoot;action=$Action;execute_requested=[bool]$Execute;writes_state=[bool]$writes;include_manual=[bool]$IncludeManual;connected_source_root=$connected;now_utc=$now.ToString("o");job_count=[int]$rows.Count;eligible_count=[int](@($rows|Where-Object{$_.eligible}).Count);execution_status=$status;rows=@($rows);blockers=@($blockers);created_utc=[DateTime]::UtcNow.ToString("o")}
$json=$receipt|ConvertTo-Json -Depth 50 -Compress;Write-Output $json;if($ok){Write-Output "LD_BACKUP_SCHEDULER_OK"}else{Write-Output "LD_BACKUP_SCHEDULER_BLOCKED"}
