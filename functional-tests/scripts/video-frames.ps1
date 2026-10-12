# Checks a recorded test video: duration, size, and N frames spread over it saved as PNG to look at
# (Read the PNGs to see what the players saw at those moments).
#   video-frames.ps1 -Video A:\StealDrive\Saved\Videos\x.mp4 [-Count 4] [-At 12,95.5] [-OutDir <dir>]
param([Parameter(Mandatory = $true)][string]$Video, [int]$Count = 4, [double[]]$At = @(), [string]$OutDir = "")
. "$PSScriptRoot\config.ps1"
if (-not (Test-Path $Video)) { "No video at $Video"; exit 1 }
if (-not $OutDir) { $OutDir = Join-Path $FT.Videos "frames" }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$info = & $FT.FFmpeg -hide_banner -i $Video 2>&1 | Out-String
$d = [regex]::Match($info, "Duration: (\d+):(\d+):([\d\.]+)")
$duration = if ($d.Success) { [int]$d.Groups[1].Value * 3600 + [int]$d.Groups[2].Value * 60 + [double]$d.Groups[3].Value } else { 0 }
$stream = [regex]::Match($info, "Video: [^\r\n]*").Value
"video: $Video"
"duration: $([math]::Round($duration, 1)) s, size: $([math]::Round((Get-Item $Video).Length / 1MB, 1)) MB"
"stream: $stream"
if ($duration -le 0) { "Could not read the duration: the file may be unfinished (ffmpeg was killed before the end)"; exit 2 }
# Rule: test videos are at least 30 fps.
$fps = [regex]::Match($stream, "([\d\.]+) fps")
if (-not $fps.Success -or [double]$fps.Groups[1].Value -lt 30) { "FAIL: the video is $(if ($fps.Success) { $fps.Groups[1].Value } else { '?' }) fps, the rule is at least 30 fps (record again: -MPVideoFPS / MPGridRecorder)"; $badFps = $true }

$times = if ($At.Count -gt 0) { $At } else { 1..$Count | ForEach-Object { [math]::Round($duration * ($_ - 0.5) / $Count, 1) } }
$base = [IO.Path]::GetFileNameWithoutExtension($Video)
foreach ($t in $times) {
    $png = Join-Path $OutDir ("{0}_{1:000.0}s.png" -f $base, $t)
    & $FT.FFmpeg -hide_banner -loglevel error -y -ss $t -i $Video -frames:v 1 -vf "scale=1280:-1" $png
    if (Test-Path $png) { "frame: $png" }
}
if ($badFps) { exit 3 }
