# Runs functional / network tests and summarizes every run.
#
#   run-tests.ps1 -Tests "Project.Functional Tests.Tests.FTEST_CauldronBrew" [-Render] [-Count 3] [-Seed N]
#   run-tests.ps1 -Tests "Project.Network.TavernShift" -Count 4
#   run-tests.ps1 -Tests "Project.Network.TavernShift" -Video            (record; network: 2x2 grid of the players)
#   run-tests.ps1 -Tests "Project.Functional Tests" -Video -UntilGreen 3 (retry until a green run, keep its video)
#
# Headless (-nullrhi) runs use UnrealEditor-Cmd. Anything rendered - network tests (PIE clients need a viewport),
# -Render, -Video (video needs rendering) - uses the full editor UnrealEditor.exe: -Cmd with rendering hits the CEF
# assert (BUseSupportedRHIRenderer). The full editor hits it rarely too: a run that crashed so is retried once.
param(
    [Parameter(Mandatory = $true)][string]$Tests,
    [int]$Count = 1,
    [switch]$Render,
    [int]$Seed = 0,
    [switch]$Video,
    [int]$UntilGreen = 0,
    [string]$Name = "",
    [string]$Extra = "",
    [int]$Steps = 20
)
. "$PSScriptRoot\config.ps1"

$network = $Tests -like "Project.Network*"
if (-not $Name) { $Name = ($Tests -replace '^Project\.', '' -replace '[^A-Za-z0-9]+', '_').Trim('_') }
if ($Video) { $Render = $true; New-Item -ItemType Directory -Force $FT.Videos | Out-Null }
if ($UntilGreen -gt 0) { $Count = $UntilGreen }
$running = Get-RunningEditors
if ($running) { "Note: an editor is already running (pid $(($running | ForEach-Object Id) -join ', ')). Two editors at once are slow and may share Saved/ files." }

$greens = 0
$runs = 0
for ($i = 1; $i -le $Count; $i++) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $log = Join-Path $FT.Logs "FT_${Name}_$stamp.log"
    $argList = @("`"$($FT.Project)`"", "-ExecCmds=`"Automation RunTests $Tests`"", '-TestExit="Automation Test Queue Empty"', '-unattended', '-nosplash', "-abslog=`"$log`"")
    if ($network -or $Render) { $argList += @('-windowed', '-ResX=1280', '-ResY=720') } else { $argList += '-nullrhi' }
    if ($Seed -ne 0) { $argList += "-MPTestSeed=$Seed" }
    if ($Video) {
        $argList += "-MPRecordVideo=`"$($FT.Videos)`""
        $argList += "-MPFFmpeg=`"$($FT.FFmpeg)`""
        if ($network) { $argList += '-MPPlayerGrid' }
    }
    if ($Extra) { $argList += $Extra }
    $rendered = $network -or $Render
    $exe = if ($rendered) { $FT.Editor } else { $FT.EditorCmd }
    $videosBefore = @(Get-ChildItem $FT.Videos -Filter *.mp4 -ErrorAction SilentlyContinue | ForEach-Object FullName)

    $runs++
    "##### run $i/$Count  ($([IO.Path]::GetFileName($exe)), $(if ($network -or $Render) { 'rendered' } else { 'headless' }))  log: $log"
    $started = Get-Date
    Start-Process -FilePath $exe -ArgumentList $argList -Wait -WindowStyle $(if ($rendered) { 'Normal' } else { 'Hidden' })
    if ((Select-String -Path $log -SimpleMatch "BUseSupportedRHIRenderer" -Quiet -ErrorAction SilentlyContinue)) {
        "CEF assert at editor start (environmental) - running once more"
        Start-Process -FilePath $exe -ArgumentList $argList -Wait -WindowStyle $(if ($rendered) { 'Normal' } else { 'Hidden' })
    }
    "duration: $([int]((Get-Date) - $started).TotalSeconds) s"
    & "$PSScriptRoot\summarize-log.ps1" -Log $log -Steps $Steps

    $failed = Select-String -Path $log -Pattern "Test Completed\. Result=\{(Fail|Error|Skipped|NotRun)\}" -Quiet
    $any = Select-String -Path $log -Pattern "Test Completed\. Result=" -Quiet
    $green = $any -and -not $failed
    $newVideos = @(Get-ChildItem $FT.Videos -Filter *.mp4 -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notin $videosBefore })
    foreach ($v in $newVideos) {
        if ($green) { "VIDEO KEPT: $($v.FullName) ($([math]::Round($v.Length / 1MB)) MB)" }
        # The file is 30 fps; warn when the game could not deliver 30 distinct pictures per second (repeated frames).
        $cap = Select-String -Path $log -Pattern "\(([\d\.]+) distinct frames per second\)" | Select-Object -Last 1
        if ($cap -and [double]$cap.Matches[0].Groups[1].Value -lt 30) { "WARNING: only $($cap.Matches[0].Groups[1].Value) distinct frames per second were captured (the rest repeat): the machine was too loaded; fewer players on screen / -ResX smaller / record again" }
        else {
            $failedName = $v.FullName -replace '\.mp4$', '_FAILED.mp4'
            Move-Item $v.FullName $failedName -Force
            "VIDEO OF A FAILED RUN: $failedName"
        }
    }
    if ($green) { $greens++ }
    if ($UntilGreen -gt 0 -and $green) { break }
}
"##### $greens green of $runs run(s)"
if ($greens -gt 0 -and ($UntilGreen -gt 0 -or $greens -eq $Count)) { exit 0 } else { exit 3 }
