# Reads an editor log of a test run and prints what matters: results, why it failed, the steps of the player that
# failed right before it, unexpected log errors, shortcuts, run reports, shift report, given-up tasks, crashes.
#   summarize-log.ps1 -Log A:\StealDrive\Saved\Logs\FT_x.log [-Steps 25] [-Lane P2_Client1]
param([Parameter(Mandatory = $true)][string]$Log, [int]$Steps = 25, [string]$Lane = "")
if (-not (Test-Path $Log)) { "No log at $Log"; exit 1 }
$lines = Get-Content -Path $Log -Encoding UTF8
function Short([string]$s, [int]$n = 600) { if ($s.Length -gt $n) { $s.Substring(0, $n) + " ..." } else { $s } }
function Body([string]$s) { ($s -replace '^\[[^\]]*\]\[[^\]]*\]', '' -replace '^LogAutomationController: (?!Error)', '' -replace '^LogTemp: Display: ', '' -replace ' \[log\] *$', '').Trim() }

"=== $Log"
# Crash (CEF assert at editor start is environmental: rerun).
$crash = $lines | Select-String -Pattern "Critical error|Assertion failed|Unhandled Exception|Fatal error" | Select-Object -First 3
if ($crash) {
    "CRASH:"; $crash | ForEach-Object { "  " + (Short (Body $_.Line) 300) }
    if ($lines | Select-String -SimpleMatch "BUseSupportedRHIRenderer") { "  -> CEF assert (browser in the editor): environmental, rerun. Network tests need UnrealEditor.exe, not -Cmd." }
}

# Results (one per test).
$results = [ordered]@{}
foreach ($m in ($lines | Select-String -Pattern "Test Completed\. Result=\{(\w+)\} Name=\{([^}]+)\}")) {
    $results[$m.Matches[0].Groups[2].Value] = $m.Matches[0].Groups[1].Value
}
if ($results.Count -eq 0) { "RESULTS: none (the run did not finish: crash, timeout or wrong test filter)" }
else { "RESULTS:"; $results.GetEnumerator() | ForEach-Object { "  $($_.Key) = $($_.Value)" } }

# Failure messages of the scenario ([game] / [timeout] / [setup]).
# Network tests log the reason in LogTemp; functional tests only in the automation controller's line
# ("FinishTest TestResult=Failed. [timeout] ..."): take the plain lines, else the controller's.
$failLines = @($lines | Where-Object { $_ -cmatch "\[(game|timeout|setup)[^\]]*\] " })
$plain = @($failLines | Where-Object { $_ -notmatch "LogAutomationController" })
$fails = $(if ($plain.Count -gt 0) { $plain } else { $failLines }) |
    ForEach-Object { (Body $_) -replace '^LogAutomationController: Error: ', '' -replace ' \[[A-Z]:\\[^\]]*\]$', '' } | Select-Object -Unique | Select-Object -First 6
if ($fails) { "FAILURES:"; $fails | ForEach-Object { "  " + (Short $_) } }

# The player (lane) that failed: its last steps.
if (-not $Lane -and $fails) {
    $m = [regex]::Match(($fails | Select-Object -First 1), "\[([A-Za-z0-9_]+)\] (Step|\w)")
    if ($m.Success -and $m.Groups[1].Value -notin @("game", "timeout")) { $Lane = $m.Groups[1].Value }
}
if ($Lane) {
    $laneSteps = $lines | Where-Object { $_ -match "\[$Lane\] (Step \d+/\d+|takes the task|gives up)" -and $_ -notmatch "LogAutomationController" } | ForEach-Object { Body $_ }
    if (-not $laneSteps) { $laneSteps = $lines | Where-Object { $_ -match "\[$Lane\] (Step \d+/\d+|takes the task|gives up)" } | ForEach-Object { Body $_ } }
    "LAST STEPS OF ${Lane}:"; $laneSteps | Select-Object -Last $Steps | ForEach-Object { "  " + (Short $_ 220) }
}
elseif ($fails) {
    $all = $lines | Where-Object { $_ -match "Step \d+/\d+:" } | ForEach-Object { Body $_ } | Select-Object -Unique
    "LAST STEPS:"; $all | Select-Object -Last $Steps | ForEach-Object { "  " + (Short $_ 220) }
}

# Errors that failed the test without a scenario failure (unexpected log errors / warnings).
$errs = $lines | Where-Object { $_ -match "LogAutomationController: Error:" -and $_ -notmatch "Test Completed|Test was aborted" -and $_ -cnotmatch "\[(game|timeout|setup)" } |
    ForEach-Object { (Body $_) -replace '^LogAutomationController: Error: ', '' } | Select-Object -Unique | Select-Object -First 10
if ($errs) { "TEST ERRORS (not from a step: unexpected log errors make a test fail; known noise goes to IgnoredLogErrors with a comment):"; $errs | ForEach-Object { "  " + (Short $_ 300) } }

$shortcuts = $lines | Select-String -Pattern "shortcut \(not the player's way\): (.*)" | ForEach-Object { $_.Matches[0].Groups[1].Value -replace ' \[log\] *$', '' } | Select-Object -Unique
if ($shortcuts) { "SHORTCUTS:"; $shortcuts | ForEach-Object { "  $_" } }

$reports = $lines | Where-Object { $_ -match "Run report: seed|Run report: \d+ approaches" -and $_ -notmatch "LogAutomationController: LogTemp" } |
    ForEach-Object { Body $_ } | Select-Object -Unique | Select-Object -First 12
if ($reports) { "RUN REPORTS:"; $reports | ForEach-Object { "  $_" } }

$shift = $lines | Select-String -Pattern "Shift report: (.*)" | Select-Object -First 1
if ($shift) {
    $text = $shift.Matches[0].Groups[1].Value -replace ' \[EMPPotionType[^\]]*\]', ''
    "SHIFT:"; $text -split ' \| ' | ForEach-Object { "  " + (Short $_ 700) }
}
$sunk = $lines | Select-String -Pattern "Ingredients sunk into.*" | Select-Object -First 1
if ($sunk) { "  " + $sunk.Matches[0].Value }
$giveups = $lines | Where-Object { $_ -match "gives up the task" -and $_ -notmatch "LogAutomationController" } | ForEach-Object { Body $_ }
if ($giveups) { "GIVEN-UP TASKS ($($giveups.Count)):"; $giveups | Select-Object -First 15 | ForEach-Object { "  " + (Short $_ 300) } }

$video = $lines | Select-String -Pattern "Recording (\d+ players to .*|finished: .*)|Could not start .* to record|video recorder stopped" | ForEach-Object { Body $_.Line } | Select-Object -Unique
if ($video) { "VIDEO:"; $video | ForEach-Object { "  $_" } }
