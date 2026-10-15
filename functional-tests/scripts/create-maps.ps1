# Creates the FTEST_* maps listed in Scripts/CreateFunctionalTestMap.py (TESTS / MAP_COPY_TESTS); existing maps
# are skipped. Close the editor first (the commandlet saves packages). Build the module first (the test class must exist).
# Then add the new .umap to Perforce yourself: p4 add <project>/Content/Tests/FTEST_<Name>.umap
# Exit codes: 0 done; 1 the commandlet failed (Python error, assertion, non-zero exit, timeout); 2 setup / editor running.
param([int]$TimeoutMinutes = 20)
try { . "$PSScriptRoot\config.ps1" } catch { "SETUP: $_"; exit 2 }
$running = Get-RunningEditors
if ($running) { "Close the editor of this project first (pid $(($running | ForEach-Object Id) -join ', '))"; exit 2 }
$script = Join-Path $FT.ProjectDir "Scripts\CreateFunctionalTestMap.py"
if (-not (Test-Path $script)) { "SETUP: $script not found"; exit 2 }
$log = Join-Path $FT.Logs "FT_CreateMaps.log"
if (Test-Path $log) { Remove-Item $log -Force }
$p = Start-Process -FilePath $FT.EditorCmd -ArgumentList "`"$($FT.Project)`"", "-run=pythonscript", "-script=`"$script`"", "-unattended", "-nosplash", "-abslog=`"$log`"" -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) { & taskkill /PID $p.Id /T /F | Out-Null; "FAILED: the commandlet did not finish in $TimeoutMinutes min (killed)"; exit 1 }
if (Test-Path $log) { Select-String -Path $log -Pattern "LogPython|Traceback|AssertionError|Success - |Failure - " | ForEach-Object { $_.Line } | Select-Object -Last 20 }
Get-ChildItem (Join-Path $FT.ProjectDir "Content\Tests") -Filter *.umap -ErrorAction SilentlyContinue | ForEach-Object { "map: $($_.Name)  $($_.LastWriteTime)" }
$broken = (-not (Test-Path $log)) -or (Select-String -Path $log -Pattern "Traceback|AssertionError|Failure - |LogPython: Error" -Quiet)
if ($p.ExitCode -ne 0 -or $broken) { "FAILED: commandlet exit code $($p.ExitCode)$(if ($broken) { ', errors in the log' }) - see $log"; exit 1 }
exit 0
