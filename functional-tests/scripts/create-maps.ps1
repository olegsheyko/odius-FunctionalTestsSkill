# Creates the FTEST_* maps listed in Scripts/CreateFunctionalTestMap.py (TESTS / MAP_COPY_TESTS); existing maps
# are skipped. Close the editor first (the commandlet saves packages). Build the module first (the test class must exist).
# Then add the new .umap to Perforce: p4 add A:/StealDrive/Content/Tests/FTEST_<Name>.umap
. "$PSScriptRoot\config.ps1"
$running = Get-RunningEditors
if ($running) { "Close the editor first (pid $(($running | ForEach-Object Id) -join ', '))"; exit 2 }
$log = Join-Path $FT.Logs "FT_CreateMaps.log"
Start-Process -FilePath $FT.EditorCmd -ArgumentList "`"$($FT.Project)`"", "-run=pythonscript", "-script=`"$($FT.ProjectDir)\Scripts\CreateFunctionalTestMap.py`"", "-unattended", "-nosplash", "-abslog=`"$log`"" -Wait -WindowStyle Hidden
Select-String -Path $log -Pattern "LogPython|Traceback|AssertionError|Success - |Failure - " | ForEach-Object { $_.Line } | Select-Object -Last 20
Get-ChildItem (Join-Path $FT.ProjectDir "Content\Tests") -Filter *.umap | ForEach-Object { "map: $($_.Name)  $($_.LastWriteTime)" }
