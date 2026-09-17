[CmdletBinding()]
param([switch]$ProbeOnly,[switch]$Resume)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$record=Join-Path $root 'maintenance/cleanup-20260916'
$manifestPath=Join-Path $record 'frozen-manifest.json'
$busy=@(Get-CimInstance Win32_Process | Where-Object {
 $_.Name -match '^(Godot.*|ffmpeg)\.exe$' -and
 ([string]$_.CommandLine).Replace('/','\').IndexOf($root,[StringComparison]::OrdinalIgnoreCase) -ge 0
})
if($busy.Count){throw 'Project engine/capture still running; stop cleanup before touching files.'}
Add-Type -Path (Join-Path $PSScriptRoot 'verified-recycle.cs')
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$bin='F:\$Recycle.Bin\'+$sid
$shell=New-Object -ComObject Shell.Application
function Records {
 foreach($f in Get-ChildItem -LiteralPath $bin -Force -File | Where-Object Name -Like '$I*') {
  $b=$null
  for($attempt=0;$attempt -lt 20;$attempt++){
   try {
    $stream=[IO.File]::Open($f.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {$memory=[IO.MemoryStream]::new();$stream.CopyTo($memory);$b=$memory.ToArray();$memory.Dispose()} finally {$stream.Dispose()}
    break
   } catch [IO.IOException] {if($attempt -eq 19){throw}; Start-Sleep -Milliseconds 100}
  }
  if($b.Length -lt 28){continue}
  $version=[BitConverter]::ToInt64($b,0)
  $offset=if($version -eq 2){28}elseif($version -eq 1){24}else{continue}
  [pscustomobject]@{original=[Text.Encoding]::Unicode.GetString($b,$offset,$b.Length-$offset).TrimEnd([char]0); metadata=$f.FullName; data=(Join-Path $bin ('$R'+$f.Name.Substring(2))); bytes=[BitConverter]::ToInt64($b,8); deleted_utc=[DateTime]::FromFileTimeUtc([BitConverter]::ToInt64($b,16)).ToString('o')}
 }
}
function Assert-Safe([string]$path) {
 $resolved=[IO.Path]::GetFullPath($path)
 if(!$resolved.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Outside root: $path"}
 $relative=[IO.Path]::GetRelativePath($root,$resolved)
 if(($relative -split '\\')[0] -in @('.git','deliverables')){throw "Protected: $path"}
 $item=Get-Item -LiteralPath $resolved -Force
 while($null -ne $item -and $item.FullName -ne $root){
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Reparse point: $($item.FullName)"}
  $item=if($item.PSIsContainer){$item.Parent}else{$item.Directory}
 }
}
function Assert-Content($entry,[string]$path,[bool]$checkTime) {
 $item=Get-Item -LiteralPath $path -Force
 $children=if($item.PSIsContainer){@(Get-ChildItem -LiteralPath $path -Recurse -Force)}else{@($item)}
 if(@($children | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0}).Count){throw "New reparse: $path"}
 $files=@($children | Where-Object {!$_.PSIsContainer})
 if($files.Count -ne $entry.file_count){throw "File count changed: $path"}
 $dirs=@($children | Where-Object PSIsContainer)
 if($dirs.Count -ne @($entry.directories).Count){throw "Directory count changed: $path"}
 foreach($f in $entry.files){
  $target=if($entry.kind -eq 'directory'){Join-Path $path $f.relative}else{$path}
  $actual=Get-Item -LiteralPath $target -Force
  if($actual.Length -ne $f.bytes){throw "Size changed: $target"}
  if($checkTime -and $null -ne $f.mtime_ns){
   $unixNanoseconds=([decimal]$actual.LastWriteTimeUtc.Ticks-621355968000000000)*100
   if($unixNanoseconds -ne [decimal]$f.mtime_ns){throw "Modification time changed: $target"}
  }
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $f.sha256){throw "Hash mismatch: $target"}
 }
}
function Recycle-One($entry) {
 if(Test-Path -LiteralPath $entry.path){
  Assert-Safe $entry.path
  Assert-Content $entry $entry.path $true
  $before=@(Records | ForEach-Object metadata)
  $started=[DateTime]::UtcNow
  [VerifiedRecycle]::Recycle($entry.path)
  $receipt=@(Records | Where-Object {$_.original -eq $entry.path -and $_.metadata -notin $before})
 } elseif($Resume){
  # Reconcile a completed move whose receipt read was interrupted. Never move again.
  $started=[DateTime]::MinValue.AddDays(1)
  $receipt=@(Records | Where-Object original -EQ $entry.path)
 } else {throw "Source missing before operation: $($entry.path)"}
 if((Test-Path -LiteralPath $entry.path) -or $receipt.Count -ne 1){throw "Missing unique receipt: $($entry.path)"}
 $r=$receipt[0]
 if(!(Test-Path -LiteralPath $r.data) -or [DateTime]$r.deleted_utc -lt $started.AddSeconds(-2)){throw 'Missing recycle data/time mismatch'}
 $visible=@($shell.Namespace(10).Items() | Where-Object Path -EQ $r.data)
 if(!$visible.Count){throw "Not visible in system Recycle Bin: $($r.data)"}
 Assert-Content $entry $r.data $false
 $r | Add-Member NoteProperty verified_file_count $entry.file_count
 $r | Add-Member NoteProperty verified_bytes $entry.bytes
 $r | Add-Member NoteProperty shell_visible $true
 $r | Add-Member NoteProperty all_file_hashes_match $true
 $r | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $record 'receipts.jsonl') -Encoding utf8
 return $r
}
$quota=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\{88aa55b5-0000-0000-0000-100000000000}'
if($quota.NukeOnDelete -ne 0){throw 'Recycle disabled'}
$entries=@(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
$existing=@(Get-ChildItem -LiteralPath $bin -Force -Recurse -File)
$used=($existing | Measure-Object Length -Sum).Sum
$planned=($entries | Measure-Object bytes -Sum).Sum
if($used+$planned+1GB -ge [long]$quota.MaxCapacity*1MB){throw 'Insufficient recycle quota; no deletion attempted'}
@{existing_bytes=$used;planned_bytes=$planned;quota_mib=$quota.MaxCapacity;manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash;timestamp=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $record 'preflight.json') -Encoding utf8
if(!$Resume){@(Records) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $record 'existing-recycle-items.json') -Encoding utf8}
$probe=Join-Path $record ('probe-'+[guid]::NewGuid().ToString()+'.txt')
[IO.File]::WriteAllText($probe,'Disposable verified recycling probe.')
$probeFile=Get-Item -LiteralPath $probe
$probeEntry=[pscustomobject]@{path=$probe;kind='file';file_count=1;bytes=$probeFile.Length;directories=@();files=@([pscustomobject]@{relative='';bytes=$probeFile.Length;sha256=(Get-FileHash -LiteralPath $probe).Hash})}
$null=Recycle-One $probeEntry
Write-Output 'Probe verified: Shell visible, $I/$R present, hash matches.'
if($ProbeOnly){exit}
$index=0
$completed=@()
if($Resume){$completed=@(Get-Content -LiteralPath (Join-Path $record 'receipts.jsonl') | ForEach-Object {($_ | ConvertFrom-Json).original})}
foreach($entry in $entries){
 if($entry.path -in $completed){
  if(Test-Path -LiteralPath $entry.path){throw 'Previously recycled path recreated; do not recycle new content.'}
  $index++;continue
 }
 $null=Recycle-One $entry
 $index++
 if($index%20 -eq 0 -or $entry.bytes -gt 100MB){Write-Output "Verified $index/$($entries.Count): $($entry.path)"}
}
$old=Get-Content -LiteralPath (Join-Path $record 'existing-recycle-items.json') -Raw | ConvertFrom-Json
foreach($r in $old){
 if(!(Test-Path -LiteralPath $r.metadata)){throw 'Pre-existing recycle metadata disappeared'}
}
# The old bin contained orphan $I records (799 bytes total before our first
# probe); absence of their $R cannot be attributed to this batch. Keep them.
$legacyAudit=@($old | ForEach-Object { [pscustomobject]@{metadata=$_.metadata;metadata_exists=(Test-Path -LiteralPath $_.metadata);data_exists_now=(Test-Path -LiteralPath $_.data);baseline_data_existence_recorded=$false} })
$legacyAudit | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $record 'legacy-recycle-audit.json') -Encoding utf8
Write-Output "ALL VERIFIED: $index targets. Baseline metadata retained; legacy data availability recorded separately."
