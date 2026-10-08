param()

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function LDBS-FullPath([string]$Path){if([string]::IsNullOrWhiteSpace($Path)){throw "STATE_PATH_REQUIRED"};return [IO.Path]::GetFullPath($Path).TrimEnd("\")}
function LDBS-IsSameOrNested([string]$Candidate,[string]$Root){$c=LDBS-FullPath $Candidate;$r=LDBS-FullPath $Root;return $c.Equals($r,[StringComparison]::OrdinalIgnoreCase)-or$c.StartsWith(($r+"\"),[StringComparison]::OrdinalIgnoreCase)}
function LDBS-Layout([string]$StateRoot){$r=LDBS-FullPath $StateRoot;return [ordered]@{root=$r;destinations=(Join-Path $r "destinations");jobs=(Join-Path $r "jobs");runs=(Join-Path $r "runs");retention=(Join-Path $r "retention");uploads=(Join-Path $r "uploads")}}
function LDBS-EnsureLayout([string]$StateRoot){$layout=LDBS-Layout $StateRoot;foreach($p in @($layout.PSObject.Properties.Value)){if(-not(Test-Path -LiteralPath ([string]$p) -PathType Container)){New-Item -ItemType Directory -Path ([string]$p) -Force|Out-Null}};return $layout}
function LDBS-ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw("STATE_FILE_MISSING:"+$Path)};return (LDREC-ConvertFromJson (Get-Content -LiteralPath $Path -Raw))}
function LDBS-Plain([object]$Value){
  if($null -eq $Value){return $null}
  if($Value -is [System.Collections.IDictionary]){$o=[ordered]@{};foreach($k in @($Value.Keys|ForEach-Object{[string]$_}|Sort-Object)){$o[$k]=LDBS-Plain $Value[$k]};return $o}
  if(($Value -is [System.Collections.IList])-or($Value -is [System.Array])){$a=@();foreach($x in $Value){$a+=,(LDBS-Plain $x)};return $a}
  if($Value -is [psobject] -and $Value -isnot [string] -and $Value -isnot [datetime]){$o=[ordered]@{};foreach($p in @($Value.PSObject.Properties|Sort-Object Name)){$o[[string]$p.Name]=LDBS-Plain $p.Value};return $o}
  return $Value
}
function LDBS-WriteImmutableJson([string]$Path,[object]$Value){$json=LDREC-ToCanonJson $Value;if(Test-Path -LiteralPath $Path -PathType Leaf){$existing=(Get-Content -LiteralPath $Path -Raw).Trim();if($existing-cne$json){throw("IMMUTABLE_STATE_COLLISION:"+$Path)};return $false};$dir=Split-Path -Parent $Path;LDREC-EnsureDir $dir;$temp=$Path+".partial";if(Test-Path -LiteralPath $temp){throw("STALE_STATE_PARTIAL:"+$temp)};LDREC-WriteUtf8NoBomLf $temp $json;[IO.File]::Move($temp,$Path);return $true}
function LDBS-AssertSchema([object]$Value,[string]$SchemaName,[string]$RepoRoot){$schemaPath=Join-Path $RepoRoot ("schemas\"+$SchemaName+".json");$schema=LDREC-ConvertFromJson (Get-Content -LiteralPath $schemaPath -Raw);LDREC-AssertReceiptAgainstSchema -Receipt $Value -Schema $schema -ExpectedSchema $SchemaName}
function LDBS-Profile([string]$DestinationRoot,[string]$RepoRoot){$path=LDDST-ProfilePath $DestinationRoot;$profile=LDBS-ReadJson $path;LDBS-AssertSchema $profile "ld.backup.destination_profile.v1" $RepoRoot;$root=LDBS-FullPath ([string]$profile.root_path);if(-not$root.Equals((LDBS-FullPath $DestinationRoot),[StringComparison]::OrdinalIgnoreCase)){throw "DESTINATION_PROFILE_ROOT_MISMATCH"};return [ordered]@{value=$profile;path=$path;sha256=(LDREC-HexSha256File $path)}}
function LDBS-Workspace([string]$WorkspaceManifestPath,[string]$RepoRoot){$path=(Resolve-Path -LiteralPath $WorkspaceManifestPath).Path;$manifest=LDBS-ReadJson $path;LDBS-AssertSchema $manifest "ld.backup.workspace_manifest.v1" $RepoRoot;if(-not([string]$manifest.workspace_root).Equals((LDBS-FullPath (Split-Path -Parent $path)),[StringComparison]::OrdinalIgnoreCase)){throw "WORKSPACE_MANIFEST_ROOT_MISMATCH"};return [ordered]@{value=$manifest;path=$path;sha256=(LDREC-HexSha256File $path)}}
