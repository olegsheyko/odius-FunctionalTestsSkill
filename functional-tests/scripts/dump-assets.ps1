# Dumps Blueprints / StateTrees / enums / DataTables / levels as readable text (MP.DumpAssets, MPAssetDump.cpp),
# to learn variable names, components, graphs and level layout before writing a test step against them.
#   dump-assets.ps1 -Paths /Game/CORE/AI/BP_GuestBase,/Game/CORE/MAPS/LS_DwarfFort [-Filter Tavern,ManagerNPC]
# Output: <project>\Saved\AssetDumps\<asset>.txt (the list is printed). Starting the editor is slow: batch all paths.
# Exit codes: 0 every path dumped; 1 some path was not dumped / editor failed or timed out; 2 setup.
param([Parameter(Mandatory = $true)][string[]]$Paths, [string[]]$Filter = @(), [int]$TimeoutMinutes = 20)
try { . "$PSScriptRoot\config.ps1" } catch { "SETUP: $_"; exit 2 }
# -ExecCmds splits commands on commas, so the filter parts are joined with '+'; plain Quit does not close the editor here.
$command = "MP.DumpAssets " + ($Paths -join " ")
if ($Filter.Count -gt 0) { $command += " Filter=" + ($Filter -join "+") }
$log = Join-Path $FT.Logs "FT_DumpAssets.log"
if (Test-Path $log) { Remove-Item $log -Force }
$before = Get-Date
$p = Start-Process -FilePath $FT.EditorCmd -ArgumentList "`"$($FT.Project)`"", "-ExecCmds=`"$command, QUIT_EDITOR`"", "-unattended", "-nullrhi", "-nosplash", "-abslog=`"$log`"" -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) { & taskkill /PID $p.Id /T /F | Out-Null; "FAILED: the editor did not finish in $TimeoutMinutes min (killed)"; exit 1 }
$dir = Join-Path $FT.ProjectDir "Saved\AssetDumps"
Get-ChildItem $dir -Filter *.txt -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $before } | ForEach-Object { "dump: $($_.FullName) ($([math]::Round($_.Length / 1KB)) KB)" }
$done = if (Test-Path $log) { @(Select-String -Path $log -Pattern "MP.DumpAssets: (\S+) -> " | ForEach-Object { $_.Matches[0].Groups[1].Value }) } else { @() }
$missing = @($Paths | Where-Object { $_ -notin $done })
if ($missing.Count -gt 0) { "FAILED: not dumped: $($missing -join ', ') (wrong path? see $log)"; exit 1 }
exit 0
