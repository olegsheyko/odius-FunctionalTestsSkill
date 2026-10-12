# Dumps Blueprints / StateTrees / enums / DataTables / levels as readable text (MP.DumpAssets, MPAssetDump.cpp),
# to learn variable names, components, graphs and level layout before writing a test step against them.
#   dump-assets.ps1 -Paths /Game/CORE/AI/BP_GuestBase,/Game/CORE/MAPS/LS_DwarfFort [-Filter Tavern,ManagerNPC]
# Output: A:\StealDrive\Saved\AssetDumps\<asset>.txt (the list is printed). Needs the editor closed? No, but it is slow
# to start: batch all paths into one call.
param([Parameter(Mandatory = $true)][string[]]$Paths, [string[]]$Filter = @())
. "$PSScriptRoot\config.ps1"
# -ExecCmds splits commands on commas, so the filter parts are joined with '+'; plain Quit does not close the editor here.
$command = "MP.DumpAssets " + ($Paths -join " ")
if ($Filter.Count -gt 0) { $command += " Filter=" + ($Filter -join "+") }
$log = Join-Path $FT.Logs "FT_DumpAssets.log"
$before = Get-Date
Start-Process -FilePath $FT.EditorCmd -ArgumentList "`"$($FT.Project)`"", "-ExecCmds=`"$command, QUIT_EDITOR`"", "-unattended", "-nullrhi", "-nosplash", "-abslog=`"$log`"" -Wait -WindowStyle Hidden
$dir = Join-Path $FT.ProjectDir "Saved\AssetDumps"
Get-ChildItem $dir -Filter *.txt | Where-Object { $_.LastWriteTime -ge $before } | ForEach-Object { "dump: $($_.FullName) ($([math]::Round($_.Length / 1KB)) KB)" }
Select-String -Path $log -Pattern "MP.DumpAssets: " | Select-Object -Last 5 | ForEach-Object { $_.Line }
