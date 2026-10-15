# Paths shared by the functional-test scripts. Dot-source it: . "$PSScriptRoot\config.ps1"
# Nothing is hard-coded to one machine:
#   project  - $env:FT_PROJECT (a .uproject) or the first folder above this script that holds one .uproject
#              (the skill lives in <project>/.claude/skills/functional-tests/scripts);
#   engine   - $env:UE_ENGINE_DIR, else the project's EngineAssociation looked up in the registry
#              (HKCU\Software\Epic Games\Unreal Engine\Builds for source builds, HKLM\SOFTWARE\EpicGames\Unreal Engine\<ver>);
#   ffmpeg   - $env:FFMPEG, else ffmpeg on the PATH (only needed for video).
# Fails with a clear message when something cannot be found, instead of running with a wrong path.
$ErrorActionPreference = "Stop"

function Find-FTProject {
    if ($env:FT_PROJECT) {
        if (-not (Test-Path $env:FT_PROJECT)) { throw "FT_PROJECT=$env:FT_PROJECT does not exist" }
        return (Resolve-Path $env:FT_PROJECT).Path
    }
    $dir = Get-Item $PSScriptRoot
    while ($dir) {
        $found = @(Get-ChildItem -Path $dir.FullName -Filter *.uproject -File -ErrorAction SilentlyContinue)
        if ($found.Count -eq 1) { return $found[0].FullName }
        if ($found.Count -gt 1) { throw "Several .uproject files in $($dir.FullName): set FT_PROJECT to the one to use" }
        $dir = $dir.Parent
    }
    throw "No .uproject found above ${PSScriptRoot}: set FT_PROJECT=<path to .uproject>"
}

function Find-FTEngine([string]$Project) {
    if ($env:UE_ENGINE_DIR) { return $env:UE_ENGINE_DIR.TrimEnd('\') }
    $assoc = (Get-Content $Project -Raw | ConvertFrom-Json).EngineAssociation
    if (-not $assoc) { throw "$Project has no EngineAssociation: set UE_ENGINE_DIR=<engine root>" }
    $builds = Get-ItemProperty "HKCU:\Software\Epic Games\Unreal Engine\Builds" -ErrorAction SilentlyContinue
    if ($builds -and $builds.PSObject.Properties[$assoc]) { return $builds.$assoc.TrimEnd('\') }
    $installed = Get-ItemProperty "HKLM:\SOFTWARE\EpicGames\Unreal Engine\$assoc" -ErrorAction SilentlyContinue
    if ($installed -and $installed.InstalledDirectory) { return $installed.InstalledDirectory.TrimEnd('\') }
    throw "Engine '$assoc' (EngineAssociation of $Project) is not registered on this machine: set UE_ENGINE_DIR=<engine root>"
}

$project = Find-FTProject
$projectDir = Split-Path $project -Parent
$engine = Find-FTEngine $project
$Global:FT = @{
    Engine      = $engine
    Project     = $project
    ProjectName = [IO.Path]::GetFileNameWithoutExtension($project)
    ProjectDir  = $projectDir
    Logs        = Join-Path $projectDir "Saved\Logs"
    Videos      = Join-Path $projectDir "Saved\Videos"
    Reports     = Join-Path $projectDir "Saved\Automation\MPFunctionalTests"
    Module      = Join-Path $projectDir "Source\MPFunctionalTests"
    Editor      = Join-Path $engine "Engine\Binaries\Win64\UnrealEditor.exe"
    EditorCmd   = Join-Path $engine "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
    Build       = Join-Path $engine "Engine\Build\BatchFiles\Build.bat"
    FFmpeg      = $null
}
foreach ($key in "Editor", "EditorCmd", "Build") {
    if (-not (Test-Path $FT[$key])) { throw "$key not found at $($FT[$key]) (engine $engine): set UE_ENGINE_DIR" }
}
if ($env:FFMPEG -and (Test-Path $env:FFMPEG)) { $Global:FT.FFmpeg = $env:FFMPEG }
elseif ($cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue) { $Global:FT.FFmpeg = $cmd.Source }
New-Item -ItemType Directory -Force $FT.Logs | Out-Null
$ErrorActionPreference = "Continue"

# Editors of THIS project only (they lock the module DLLs); editors/cooks of other projects do not matter.
function Get-RunningEditors {
    $pattern = [regex]::Escape("$($FT.ProjectName).uproject")
    Get-CimInstance Win32_Process -Filter "Name='UnrealEditor.exe' OR Name='UnrealEditor-Cmd.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $pattern } |
        ForEach-Object { [pscustomobject]@{ ProcessName = $_.Name; Id = $_.ProcessId } }
}

function Require-FFmpeg {
    if (-not $FT.FFmpeg) { throw "ffmpeg not found: install it (on the PATH) or set FFMPEG=<path to ffmpeg.exe>" }
}
