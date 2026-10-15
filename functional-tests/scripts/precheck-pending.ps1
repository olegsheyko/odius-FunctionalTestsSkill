# Before a submit: does the pending changelist build on top of the LATEST depot (what a teammate gets after sync)?
#   1. exports the depot head of Source/, Config/ and the .uproject into a separate short folder (your workspace is not touched);
#   2. builds it (proves the head itself is fine);
#   3. copies your opened Source files over it (edits and adds; deletes are removed) and builds again;
#   4. lists the opened files, so they go in ONE changelist.
#   precheck-pending.ps1 [-WorkDir C:\FTpc] [-Keep]
# Exit codes: 0 head and head+pending build; 1 head is broken; 3 pending breaks the build; 2 setup (p4, paths).
# A first build of the copy is a full build (several minutes). The work folder must have a short path (UBT: 260 chars).
param([string]$WorkDir = "", [switch]$Keep)
try { . "$PSScriptRoot\config.ps1" } catch { "SETUP: $_"; exit 2 }
if (-not (Get-Command p4 -ErrorAction SilentlyContinue)) { "SETUP: p4 not found"; exit 2 }
Push-Location $FT.ProjectDir
try {
    $where = (& p4 -ztag -F "%depotFile%" where "$($FT.Project)" 2>$null | Select-Object -First 1)
    if (-not $where) { "SETUP: $($FT.Project) is not in the Perforce workspace (p4 where; logged in?)"; exit 2 }
    $depotRoot = $where -replace '/[^/]+$', ''
    if (-not $WorkDir) { $WorkDir = (Split-Path $FT.ProjectDir -Qualifier) + "\FTpc" }
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
    New-Item -ItemType Directory -Force $WorkDir | Out-Null

    # 1. Depot head export.
    $files = @(& p4 -ztag -F "%depotFile%" files -e "$depotRoot/Source/..." "$depotRoot/Config/..." "$depotRoot/*.uproject" 2>$null)
    if ($files.Count -eq 0) { "SETUP: no depot files under $depotRoot"; exit 2 }
    foreach ($f in $files) {
        $rel = $f.Substring($depotRoot.Length + 1)
        $target = Join-Path $WorkDir $rel
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        & p4 print -q -o "$target" "$f#head" 2>$null | Out-Null
    }
    Get-ChildItem $WorkDir -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }
    "exported $($files.Count) depot head files to $WorkDir"
    $copyProject = Join-Path $WorkDir (Split-Path $FT.Project -Leaf)
    $target = "$($FT.ProjectName)Editor"

    # Prints with Write-Host: a PowerShell function returns everything it outputs, and this one must return only the result.
    function Build-Copy([string]$Label) {
        Write-Host "--- build: $Label"
        $out = & $FT.Build $target Win64 Development "-Project=$copyProject" -WaitMutex 2>&1
        $ok = ($LASTEXITCODE -eq 0) -and [bool]($out | Select-String -SimpleMatch "Result: Succeeded")
        $out | Select-String -Pattern "error C\d+|error LNK|fatal error|BuildException|Result:" | Select-Object -First 40 | ForEach-Object { Write-Host ("  " + $_.Line.Trim()) }
        if (-not $ok) { Write-Host "  (full log: $env:LOCALAPPDATA\UnrealBuildTool\Log.txt)" }
        return $ok
    }

    # 2. Head alone.
    if (-not (Build-Copy "depot head")) { "HEAD IS BROKEN: the depot itself does not build (not your pending)"; exit 1 }

    # 3. Head + your opened files.
    $opened = @(& p4 -ztag -F "%depotFile%|%action%" opened "$depotRoot/..." 2>$null)
    $applied = @()
    foreach ($line in $opened) {
        $depotFile, $action = $line -split '\|'
        if ($depotFile -notmatch '/(Source|Config)/|\.uproject$') { continue }
        $rel = $depotFile.Substring($depotRoot.Length + 1)
        $copy = Join-Path $WorkDir $rel
        if ($action -match 'delete') { if (Test-Path $copy) { Remove-Item $copy -Force }; $applied += "$action $rel"; continue }
        $local = Join-Path $FT.ProjectDir $rel
        New-Item -ItemType Directory -Force (Split-Path $copy) | Out-Null
        Copy-Item $local $copy -Force
        # Copy-Item keeps the old modification time; older than the objects just built, UBT would not recompile it.
        (Get-Item $copy).LastWriteTime = Get-Date
        $applied += "$action $rel"
    }
    if ($applied.Count -eq 0) { "No opened Source/Config files: nothing to check on top of the head."; exit 0 }
    "pending applied:"; $applied | ForEach-Object { "  $_" }
    if (-not (Build-Copy "depot head + pending")) { "PENDING BREAKS THE BUILD on top of the latest depot: fix before submitting"; exit 3 }

    "OK: the depot head builds, and your pending builds on top of it."
    "Submit these together, in ONE changelist (plus non-code files you opened, e.g. maps):"
    $opened | ForEach-Object { "  " + ($_ -replace '\|', '  ') }
    exit 0
}
finally {
    Pop-Location
    if (-not $Keep -and $WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
