param([string]$FfmpegPath = 'F:\Documents\楚物志\artifacts\media-20260909\toolchain\ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'InheritanceTasks\Audio\water-cow-v1'
[IO.Directory]::CreateDirectory($output) | Out-Null
Add-Type -AssemblyName System.Speech
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice.SelectVoice('Microsoft Huihui Desktop')
$voice.Rate = 4
$lines = @('相传马宗岭驻军缺粮，士兵拉犁开荒。','刘备调来耕牛，帮助军民种田。','牧牛人发现洞穴，把牛群安置其中。','战后有牛逃出后洞，水牛洞之名流传。')
$records = @()
for ($index = 0; $index -lt 4; $index++) {
    $original = Join-Path $output ('narration-{0}-source.wav' -f ($index+1))
    $derived = Join-Path $output ('narration-{0}.ogg' -f ($index+1))
    $voice.SetOutputToWaveFile($original)
    $voice.Speak($lines[$index])
    $voice.SetOutputToNull()
    & $FfmpegPath -v error -y -i $original -af 'apad=whole_dur=3' -ar 44100 -c:a libvorbis -q:a 5 $derived
    if ($LASTEXITCODE -ne 0) { throw '旁白转换失败' }
    $records += @{scene=$index+1; text=$lines[$index]; original=[IO.Path]::GetFileName($original); audio=[IO.Path]::GetFileName($derived); sha256=(Get-FileHash -LiteralPath $derived -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$voice.Dispose()
$manifest = @{version=1; source='https://news.hubeidaily.net/pc/c_2714369.html'; classification='下堡坪乡马宗岭村地方传说；重新简编，不作为确证历史'; voice='Microsoft Huihui Desktop / Windows offline SAPI'; rate=4; newly_generated=$true; scenes=$records}
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),($manifest | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
