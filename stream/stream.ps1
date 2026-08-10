# =============================================================================
#  stream.ps1 - run ONE continuous YouTube live stream from a channel playlist
#  - downloads the assigned videos (newest first), builds playlist.txt
#  - pushes a seamless loop to YouTube RTMP via ffmpeg
#  - self-heals: if ffmpeg dies for any reason it restarts in a few seconds
#    (alternating primary / backup ingest endpoints)
# =============================================================================
param(
  [string]$ChannelUrl,
  [int]$Index = 1,
  [int]$Count = 1,
  [string]$OutDir = "$env:USERPROFILE\videos",
  [string]$StreamKey = "",
  [string]$Rtmp = "rtmp://a.rtmp.youtube.com/live2",
  [string]$RtmpBackup = "rtmp://b.rtmp.youtube.com/live2?backup=1"
)

$ErrorActionPreference = "Stop"
if (-not $StreamKey) { throw "StreamKey is empty - cannot stream without it" }

$tool = Join-Path $PWD "stream\tool.py"
Write-Output "== downloading + building playlist (stream $Index/$Count) =="
python $tool agent "$ChannelUrl" $Index $Count "$OutDir"
if ($LASTEXITCODE -ne 0) { throw "tool.py failed with exit $LASTEXITCODE" }

$playlist = Join-Path $OutDir "playlist.txt"
if (-not (Test-Path $playlist)) { throw "playlist not created: $playlist" }

$primary = "$Rtmp/$StreamKey"
$backup  = "$RtmpBackup/$StreamKey"
$target  = $primary

$common = @(
  "-re","-stream_loop","-1","-f","concat","-safe","0","-i",$playlist,
  "-vf","scale=1280:720",
  "-c:v","libx264","-preset","veryfast","-b:v","2500k","-maxrate","2500k","-bufsize","5000k",
  "-pix_fmt","yuv420p","-g","60",
  "-c:a","aac","-b:a","128k","-ar","44100",
  "-f","flv"
)

$start = Get-Date
while ($true) {
  Write-Output "[$((Get-Date).ToString('HH:mm:ss'))] starting ffmpeg -> $target"
  & ffmpeg -hide_banner -loglevel warning @common $target
  $code = $LASTEXITCODE
  Write-Output "[$((Get-Date).ToString('HH:mm:ss'))] ffmpeg exited (code $code) after $([math]::Round(((Get-Date)-$start).TotalMinutes,1)) min - restarting in 5s"
  Start-Sleep -Seconds 5
  if ($target -eq $primary) { $target = $backup } else { $target = $primary }
}
