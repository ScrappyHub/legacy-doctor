param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$Producer = "legacy-doctor",
  [string]$ProducerInstance = $env:COMPUTERNAME,
  [string]$EventType = "legacy_doctor.dev.commit.v1",
  [string[]]$PrevLinks = @(),
  [ValidateSet("evidence","deterministic")][string]$Strength = "evidence",
  [string]$ContentRef = "sealed",
  [string]$Principal = ("single-tenant/device_agent/device/" + $env:COMPUTERNAME),
  [string]$ProducerKeyId = "ld-dev-key",
  [string]$SshNamespace = "nfl"
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8Lf([string]$path,[string]$text){ EnsureDir (Split-Path -Parent $path); $lf = ($text -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf += "`n" }; [IO.File]::WriteAllText($path,$lf,(Utf8NoBom)) }
function AppendUtf8Lf([string]$path,[string]$line){ EnsureDir (Split-Path -Parent $path); $enc=(Utf8NoBom); $lf = ($line -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf += "`n" }; [IO.File]::AppendAllText($path,$lf,$enc) }
function Canon($v){
  if($null -eq $v){ return $null }
  if($v -is [string] -or $v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal] -or $v -is [bool]){ return $v }
  if($v -is [System.Collections.IDictionary]){
    $keys=@($v.Keys|ForEach-Object{[string]$_}|Sort-Object)
    $o=[ordered]@{}
    foreach($k in $keys){ $o[$k]=Canon $v[$k] }
    return $o
  }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $a=@()
    foreach($x in $v){ $a += ,(Canon $x) }
    return $a
  }
  return ([string]$v)
}
function ToCanonJson($v){ (Canon $v) | ConvertTo-Json -Depth 50 -Compress }
function Sha256HexBytes([byte[]]$b){ if($null -eq $b){ $b=[byte[]]@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try { $h=$sha.ComputeHash($b); $sb=New-Object System.Text.StringBuilder; foreach($x in $h){ [void]$sb.Append($x.ToString("x2")) }; return $sb.ToString() } finally { $sha.Dispose() } }
function Sha256HexFile([string]$p){ if(-not (Test-Path -LiteralPath $p)){ Die ("MISSING_FILE: "+$p) }; return (Sha256HexBytes ([IO.File]::ReadAllBytes($p))) }
function FindSshKeygen(){ $c=Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue; if($c){ return $c.Source }; $c2=Get-Command ssh-keygen -ErrorAction SilentlyContinue; if($c2){ return $c2.Source }; Die "SSH_KEYGEN_NOT_FOUND" }
function EnsureEd25519Keypair([string]$PrivKeyPath){
  $pub=$PrivKeyPath+".pub"
  EnsureDir (Split-Path -Parent $PrivKeyPath)
  if(-not (Test-Path -LiteralPath $PrivKeyPath)){
    $ssh=FindSshKeygen
    $arg = "-t ed25519 -N """" -f ""$PrivKeyPath"""
    $p=Start-Process -FilePath $ssh -ArgumentList $arg -NoNewWindow -Wait -PassThru
    if($p.ExitCode -ne 0){ Die ("KEYGEN_FAILED exit="+$p.ExitCode) }
  }
  if(-not (Test-Path -LiteralPath $PrivKeyPath)){ Die ("KEYGEN_FAILED missing priv: "+$PrivKeyPath) }
  if(-not (Test-Path -LiteralPath $pub)){ Die ("KEYGEN_FAILED missing pub: "+$pub) }
  return $PrivKeyPath
}
function SshSignDetached([string]$PrivKey,[string]$Namespace,[string]$MessageFile,[string]$OutSig){
  $ssh=FindSshKeygen
  EnsureDir (Split-Path -Parent $OutSig)
  if(Test-Path -LiteralPath $OutSig){ Remove-Item -LiteralPath $OutSig -Force }
  & $ssh -Y sign -f $PrivKey -n $Namespace $MessageFile | Out-Null
  $gen=$MessageFile+".sig"
  if(-not (Test-Path -LiteralPath $gen)){ Die "SIGN_FAILED: ssh-keygen did not emit .sig" }
  Move-Item -LiteralPath $gen -Destination $OutSig -Force
}
function WriteSha256Sums([string]$RootDir,[string[]]$RelFiles,[string]$OutPath){
  $lines=New-Object System.Collections.Generic.List[string]
  foreach($rf in @(@($RelFiles)|Sort-Object)){
    $p=Join-Path $RootDir ($rf -replace "/","\")
    if(-not (Test-Path -LiteralPath $p)){ Die ("SHA_MISSING: "+$rf) }
    $h=Sha256HexFile $p
    [void]$lines.Add(("{0}  {1}" -f $h,$rf))
  }
  WriteUtf8Lf $OutPath (($lines.ToArray()-join "`n"))
}
function BuildPacket_PCV1_OptionA([string]$OutboxRoot,[string]$Producer,[string]$CommitHash,[hashtable]$PayloadFilesByRelPath,[string]$SignerPrivKey,[string]$SignerNamespace){
  EnsureDir $OutboxRoot
  $stage=Join-Path $OutboxRoot ("_staging_"+[Guid]::NewGuid().ToString("n"))
  EnsureDir $stage; EnsureDir (Join-Path $stage "payload"); EnsureDir (Join-Path $stage "signatures")
  $payloadRel=New-Object System.Collections.Generic.List[string]
  foreach($k in @($PayloadFilesByRelPath.Keys)){
    $rel=[string]$k
    if(-not $rel.StartsWith("payload/")){ Die ("PAYLOAD_REL_MUST_START_payload/: "+$rel) }
    $src=[string]$PayloadFilesByRelPath[$k]
    if(-not (Test-Path -LiteralPath $src)){ Die ("PAYLOAD_SRC_MISSING: "+$src) }
    $dst=Join-Path $stage ($rel -replace "/","\")
    EnsureDir (Split-Path -Parent $dst)
    Copy-Item -LiteralPath $src -Destination $dst -Force
    [void]$payloadRel.Add($rel)
  }
  $manifestObj=[ordered]@{ schema="packet.manifest.v1"; producer=$Producer; commit_hash=$CommitHash; created_time=([DateTime]::UtcNow.ToString("o")); files=@(@(@($payloadRel.ToArray()|Sort-Object)) + @("manifest.json","packet_id.txt","signatures/producer.sig","sha256sums.txt")) }
  $manifestJson=(ToCanonJson $manifestObj)
  $manifestPath=Join-Path $stage "manifest.json"
  WriteUtf8Lf $manifestPath $manifestJson
  $packetId = Sha256HexBytes ([Text.Encoding]::UTF8.GetBytes(($manifestJson + "`n")))
  $packetIdPath=Join-Path $stage "packet_id.txt"
  WriteUtf8Lf $packetIdPath $packetId
  $msgPath=Join-Path $stage "packet.msg.txt"
  WriteUtf8Lf $msgPath ($CommitHash + "`n" + $packetId + "`n")
  $sigOut=Join-Path $stage "signatures\producer.sig"
  SshSignDetached -PrivKey $SignerPrivKey -Namespace $SignerNamespace -MessageFile $msgPath -OutSig $sigOut
  if(Test-Path -LiteralPath $msgPath){ Remove-Item -LiteralPath $msgPath -Force }
  $shaPath=Join-Path $stage "sha256sums.txt"
  $relAll = @(@(@($payloadRel.ToArray()|Sort-Object)) + @("manifest.json","packet_id.txt","signatures/producer.sig"))
  WriteSha256Sums -RootDir $stage -RelFiles $relAll -OutPath $shaPath
  $final=Join-Path $OutboxRoot $packetId
  if(Test-Path -LiteralPath $final){ Remove-Item -LiteralPath $stage -Recurse -Force; return $final }
  Move-Item -LiteralPath $stage -Destination $final -Force
  return $final
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ld = Join-Path $RepoRoot ".nfl\pledges"
$commitDir = Join-Path $ld "commits"
$logPath = Join-Path $ld "pledge_log.ndjson"
$outbox = Join-Path $RepoRoot "packets\outbox"
$keyPath = Join-Path $RepoRoot "proofs\keys\legacy-doctor-dev-ed25519"
EnsureDir $commitDir; EnsureDir $outbox; $keyPath = EnsureEd25519Keypair $keyPath
$eventTime = [DateTime]::UtcNow.ToString("o")
$payloadObj = [ordered]@{ schema="commitment.v1"; producer=$Producer; producer_instance=$ProducerInstance; event_type=$EventType; event_time=$eventTime; prev_links=@(@($PrevLinks)); content_ref=$ContentRef; strength=$Strength }
$payloadJson = ToCanonJson $payloadObj
$commitHash = Sha256HexBytes ([Text.Encoding]::UTF8.GetBytes(($payloadJson + "`n")))
$payloadPath = Join-Path $commitDir ("commit.payload." + $commitHash + ".json")
WriteUtf8Lf $payloadPath $payloadJson
$msg = ($commitHash + "`n" + $Principal + "`n")
$msgPath = Join-Path $commitDir ("commit.msg." + $commitHash + ".txt")
WriteUtf8Lf $msgPath $msg
$sigPath = Join-Path $commitDir ("commit.sig." + $commitHash + ".sig")
SshSignDetached -PrivKey $keyPath -Namespace $SshNamespace -MessageFile $msgPath -OutSig $sigPath
$prevLogHash = ("0"*64); $seq = 1
if(Test-Path -LiteralPath $logPath){
  $last = (Get-Content -LiteralPath $logPath -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -Last 1)
  if($last){ try { $o = $last | ConvertFrom-Json; if($o.local_record_hash){ $prevLogHash = [string]$o.local_record_hash }; if($o.local_sequence){ $seq = ([int]$o.local_sequence) + 1 } } catch { Die ("PLEDGE_LOG_PARSE_FAILED: " + $logPath) } }
}
$recObj = [ordered]@{ schema="local.pledge.v1"; commit_hash=$commitHash; producer=$Producer; producer_instance=$ProducerInstance; event_type=$EventType; producer_time=$eventTime; prev_links=@(@($PrevLinks)); strength=$Strength; content_ref=$ContentRef; producer_principal=$Principal; producer_key_id=$ProducerKeyId; payload_path=(".nfl/pledges/commits/commit.payload." + $commitHash + ".json"); sig_path=(".nfl/pledges/commits/commit.sig." + $commitHash + ".sig"); local_sequence=$seq; local_prev_log_hash=$prevLogHash }
$recJson = ToCanonJson $recObj
$recHash = Sha256HexBytes ([Text.Encoding]::UTF8.GetBytes(($recJson + "`n")))
$recObj2 = $recObj.Clone(); $recObj2["local_record_hash"] = $recHash
AppendUtf8Lf $logPath (ToCanonJson $recObj2)
Write-Host ("COMMIT_OK: " + $commitHash) -ForegroundColor Green
Write-Host ("PLEDGE_OK: seq=" + $seq + " record_hash=" + $recHash) -ForegroundColor Green
$ingestObj = [ordered]@{ schema="nfl.ingest.v1"; commit_hash=$commitHash; producer=$Producer; producer_sig="sigfile:signatures/producer.sig"; producer_key_id=$ProducerKeyId; producer_principal=$Principal; prev_links=@(@($PrevLinks)); event_type=$EventType; producer_time=$eventTime; payload_bytes_mode="plaintext_commit_payload_only" }
$ingestJson = ToCanonJson $ingestObj
$ingestPath = Join-Path $commitDir ("ingest." + $commitHash + ".json")
WriteUtf8Lf $ingestPath $ingestJson
$payloadMap = @{ "payload/ingest.json" = $ingestPath; "payload/commit.payload.json" = $payloadPath }
$packetDir = BuildPacket_PCV1_OptionA -OutboxRoot $outbox -Producer $Producer -CommitHash $commitHash -PayloadFilesByRelPath $payloadMap -SignerPrivKey $keyPath -SignerNamespace $SshNamespace
Write-Host ("NFL_PACKET_OK: " + $packetDir) -ForegroundColor Cyan
$commitHash
