# Runs functional / network tests and summarizes every run.
#
#   run-tests.ps1 -Tests "Project.Functional Tests.Tests.FTEST_CauldronBrew" [-Render] [-Count 3] [-Seed N]
#   run-tests.ps1 -Tests "Project.Network.TavernShift" -Count 4
#   run-tests.ps1 -Tests "Project.Network.TavernShift" -Video            (record; network: 2x2 grid of the players)
#   run-tests.ps1 -Tests "Project.Functional Tests" -Video -UntilGreen 3 (retry until a green run, keep its video)
#
# Headless (-nullrhi) runs use UnrealEditor-Cmd. Anything rendered - network tests (PIE clients need a viewport),
# -Render, -Video (video needs rendering) - uses the full editor UnrealEditor.exe: -Cmd with rendering hits the CEF
# assert (BUseSupportedRHIRenderer). The full editor hits it rarely too: such a run is retried once; the log of the
# crashed attempt is kept (<log>_cefcrash.log) and the attempt is reported.
#
# A run is GREEN only when all of these hold:
#   - the editor exited by itself within -TimeoutMinutes (a hung editor is killed, the run is red);
#   - its exit code is 0 and the log has no crash ("Critical error", "Fatal error", "Unhandled Exception");
#   - the log says how many tests the filter found (> 0) and every one of them completed;
#   - none completed with Fail / Error / Skipped / NotRun;
#   - with -Video: an MP4 was written for the run and passes video-frames.ps1 (>= 30 fps).
# Exit code: 0 when every run is green (-Count), or when a green run was found (-UntilGreen); 3 otherwise; 2 bad setup.
# -UntilGreen is for getting ONE good recording; it says nothing about stability - for that run a series (-Count N).
param(
    [Parameter(Mandatory = $true)][string]$Tests,
    [int]$Count = 1,
    [switch]$Render,
    [int]$Seed = 0,
    [switch]$Video,
    [int]$UntilGreen = 0,
    [string]$Name = "",
    [string]$Extra = "",
    [int]$Steps = 20,
    [int]$TimeoutMinutes = 45
)
try { . "$PSScriptRoot\config.ps1" } catch { "SETUP: $_"; exit 2 }

$network = $Tests -like "Project.Network*"
if (-not $Name) { $Name = ($Tests -replace '^Project\.', '' -replace '[^A-Za-z0-9]+', '_').Trim('_') }
if ($Video) {
    try { Require-FFmpeg } catch { "SETUP: $_"; exit 2 }
    $Render = $true
    New-Item -ItemType Directory -Force $FT.Videos | Out-Null
}
if ($UntilGreen -gt 0) {
    $Count = $UntilGreen
    "Note: -UntilGreen stops at the first green run (for a recording). It does not show stability: use -Count N for that."
}
$running = Get-RunningEditors
if ($running) { "Note: an editor of this project is already running (pid $(($running | ForEach-Object Id) -join ', ')). Two editors at once are slow and share Saved/ files." }
$rendered = $network -or $Render
$exe = if ($rendered) { $FT.Editor } else { $FT.EditorCmd }

# Starts the editor and waits for it at most TimeoutMinutes; returns @{ ExitCode; TimedOut }.
function Invoke-Editor([string[]]$ArgList) {
    $p = Start-Process -FilePath $exe -ArgumentList $ArgList -PassThru -WindowStyle $(if ($rendered) { 'Normal' } else { 'Hidden' })
    if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        # Kill the editor with its children (ffmpeg of a recording, shader workers).
        & taskkill /PID $p.Id /T /F | Out-Null
        return @{ ExitCode = -1; TimedOut = $true }
    }
    return @{ ExitCode = $p.ExitCode; TimedOut = $false }
}

$greens = 0
$runs = 0
for ($i = 1; $i -le $Count; $i++) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $log = Join-Path $FT.Logs "FT_${Name}_$stamp.log"
    $argList = @("`"$($FT.Project)`"", "-ExecCmds=`"Automation RunTests $Tests`"", '-TestExit="Automation Test Queue Empty"', '-unattended', '-nosplash', "-abslog=`"$log`"")
    if ($rendered) { $argList += @('-windowed', '-ResX=1280', '-ResY=720') } else { $argList += '-nullrhi' }
    if ($Seed -ne 0) { $argList += "-MPTestSeed=$Seed" }
    if ($Video) {
        $argList += "-MPRecordVideo=`"$($FT.Videos)`""
        $argList += "-MPFFmpeg=`"$($FT.FFmpeg)`""
        if ($network) { $argList += '-MPPlayerGrid' }
    }
    if ($Extra) { $argList += $Extra }
    $videosBefore = @(Get-ChildItem $FT.Videos -Filter *.mp4 -ErrorAction SilentlyContinue | ForEach-Object FullName)

    $runs++
    "##### run $i/$Count  ($([IO.Path]::GetFileName($exe)), $(if ($rendered) { 'rendered' } else { 'headless' }), timeout $TimeoutMinutes min)  log: $log"
    $started = Get-Date
    $proc = Invoke-Editor $argList
    if ((Test-Path $log) -and (Select-String -Path $log -SimpleMatch "BUseSupportedRHIRenderer" -Quiet)) {
        # Keep the evidence of the first attempt; the retry writes a fresh log.
        $crashLog = $log -replace '\.log$', '_cefcrash.log'
        Move-Item $log $crashLog -Force
        "CEF assert at editor start (environmental): log kept as $crashLog - running once more"
        $proc = Invoke-Editor $argList
    }
    "duration: $([int]((Get-Date) - $started).TotalSeconds) s, editor exit code: $($proc.ExitCode)$(if ($proc.TimedOut) { ' (TIMED OUT, killed)' })"

    $reasons = @()
    if ($proc.TimedOut) { $reasons += "the editor did not finish in $TimeoutMinutes min and was killed" }
    elseif ($proc.ExitCode -ne 0) { $reasons += "editor exit code $($proc.ExitCode)" }
    if (-not (Test-Path $log)) {
        $reasons += "no log written ($log)"
    }
    else {
        & "$PSScriptRoot\summarize-log.ps1" -Log $log -Steps $Steps
        if (Select-String -Path $log -Pattern "Critical error|Fatal error|Unhandled Exception" -Quiet) { $reasons += "the editor crashed" }
        $foundLine = Select-String -Path $log -Pattern "Found (\d+) automation tests? based on" | Select-Object -First 1
        $found = if ($foundLine) { [int]$foundLine.Matches[0].Groups[1].Value } else { 0 }
        $completed = @{}
        foreach ($m in (Select-String -Path $log -Pattern "Test Completed\. Result=\{(\w+)\} Name=\{([^}]+)\}")) {
            $completed[$m.Matches[0].Groups[2].Value] = $m.Matches[0].Groups[1].Value
        }
        if ($found -eq 0) { $reasons += "the filter found no tests (check -Tests: '$Tests')" }
        elseif ($completed.Count -lt $found) { $reasons += "only $($completed.Count) of $found tests completed" }
        $bad = @($completed.GetEnumerator() | Where-Object { $_.Value -ne "Success" } | ForEach-Object { "$($_.Key)=$($_.Value)" })
        if ($bad.Count -gt 0) { $reasons += "not passed: $($bad -join ', ')" }
    }

    # Video: requested -> must exist and be >= 30 fps; the file of a red run is marked _FAILED.
    $newVideos = @(Get-ChildItem $FT.Videos -Filter *.mp4 -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notin $videosBefore })
    if ($Video -and $newVideos.Count -eq 0) { $reasons += "video requested but no MP4 was written" }
    foreach ($v in $newVideos) {
        & "$PSScriptRoot\video-frames.ps1" -Video $v.FullName -Count 0 | Where-Object { $_ -match "duration|stream|FAIL" }
        if ($LASTEXITCODE -ne 0) { $reasons += "video $($v.Name) failed the check (exit $LASTEXITCODE)" }
        $cap = if (Test-Path $log) { Select-String -Path $log -Pattern "\(([\d\.]+) distinct frames per second\)" | Select-Object -Last 1 }
        if ($cap -and [double]$cap.Matches[0].Groups[1].Value -lt 30) { "WARNING: only $($cap.Matches[0].Groups[1].Value) distinct frames per second were captured (the rest repeat): the machine was too loaded; record again with fewer things running" }
    }
    $green = $reasons.Count -eq 0
    foreach ($v in $newVideos) {
        if ($green) { "VIDEO KEPT: $($v.FullName) ($([math]::Round($v.Length / 1MB)) MB)" }
        else {
            $failedName = $v.FullName -replace '\.mp4$', '_FAILED.mp4'
            Move-Item $v.FullName $failedName -Force
            "VIDEO OF A RED RUN: $failedName"
        }
    }
    if ($green) { $greens++; "RUN ${i}: GREEN" } else { "RUN ${i}: RED - $($reasons -join '; ')" }
    if ($UntilGreen -gt 0 -and $green) { break }
}
"##### $greens green of $runs run(s)"
if ($UntilGreen -gt 0) { if ($greens -gt 0) { exit 0 } else { exit 3 } }
if ($greens -eq $runs -and $runs -gt 0) { exit 0 } else { exit 3 }
