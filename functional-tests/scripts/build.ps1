# Builds the editor target of the project (<Project>Editor: game + MPFunctionalTests). Prints errors, warnings, result.
# Exit codes: 0 built; 1 compile/link error (or no "Result: Succeeded" in the output); 2 setup problem or an editor of
# this project is running (it locks the module DLLs - close it first, or -Force).
param([switch]$Force, [string]$Target = "")
try { . "$PSScriptRoot\config.ps1" } catch { "SETUP: $_"; exit 2 }
if (-not $Target) { $Target = "$($FT.ProjectName)Editor" }

$running = Get-RunningEditors
if ($running -and -not $Force) {
    "An editor of this project is running (it locks the module DLLs): " + (($running | ForEach-Object { "$($_.ProcessName) pid $($_.Id)" }) -join ", ")
    "Close it (or wait for the test run to end), then build again. -Force builds anyway (link errors likely)."
    exit 2
}
$output = & $FT.Build $Target Win64 Development "-Project=$($FT.Project)" -WaitMutex 2>&1
$code = $LASTEXITCODE
$output | Select-String -Pattern "error|warning C\d+|Result:" | ForEach-Object { $_.Line }
# Both must agree: the build tool's exit code and its own result line.
if ($code -eq 0 -and ($output | Select-String -SimpleMatch "Result: Succeeded")) { exit 0 }
"BUILD FAILED (exit code $code). Full log: $env:LOCALAPPDATA\UnrealBuildTool\Log.txt"
exit 1
