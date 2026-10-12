# Paths shared by the functional-test scripts. Dot-source it: . "$PSScriptRoot\config.ps1"
$Global:FT = @{
    Engine      = "E:\UnrealEngineDEV\UEVer\UE_5.7"
    Project     = "A:\StealDrive\MonsterPotion.uproject"
    ProjectDir  = "A:\StealDrive"
    FFmpeg      = "E:\ffmpeg\ffmpeg.exe"
    Logs        = "A:\StealDrive\Saved\Logs"
    Videos      = "A:\StealDrive\Saved\Videos"
    Reports     = "A:\StealDrive\Saved\Automation\MPFunctionalTests"
    Module      = "A:\StealDrive\Source\MPFunctionalTests"
}
$Global:FT.Editor    = Join-Path $FT.Engine "Engine\Binaries\Win64\UnrealEditor.exe"
$Global:FT.EditorCmd = Join-Path $FT.Engine "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$Global:FT.Build     = Join-Path $FT.Engine "Engine\Build\BatchFiles\Build.bat"

# Editors of THIS project only (they lock the module DLLs); editors/cooks of other projects do not matter.
function Get-RunningEditors {
    Get-CimInstance Win32_Process -Filter "Name='UnrealEditor.exe' OR Name='UnrealEditor-Cmd.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'MonsterPotion\.uproject' } |
        ForEach-Object { [pscustomobject]@{ ProcessName = $_.Name; Id = $_.ProcessId } }
}
