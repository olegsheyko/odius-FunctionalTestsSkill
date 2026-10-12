# Builds MonsterPotionEditor (game + MPFunctionalTests). Prints only errors, warnings and the result.
# Exit codes: 0 built, 1 compile/link error, 2 an editor is running (it locks the DLLs; close it first).
param([switch]$Force)
. "$PSScriptRoot\config.ps1"

$running = Get-RunningEditors
if ($running -and -not $Force) {
    "An editor is running (it locks the module DLLs): " + (($running | ForEach-Object { "$($_.ProcessName) pid $($_.Id)" }) -join ", ")
    "Close it (or wait for the test run to end), then build again. -Force builds anyway (live coding / link errors likely)."
    exit 2
}
$output = & $FT.Build MonsterPotionEditor Win64 Development "-Project=$($FT.Project)" -WaitMutex 2>&1
$output | Select-String -Pattern "error|warning C\d+|Result:" | ForEach-Object { $_.Line }
if (($output | Select-String -SimpleMatch "Result: Succeeded")) { exit 0 } else { exit 1 }
