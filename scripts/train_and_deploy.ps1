param(
    [string]$Csv = "",
    [switch]$SkipCppBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pythonDir = Join-Path $root "python"
$mt5Files = Join-Path $root "mt5\Files"
$mt5Libraries = Join-Path $root "mt5\Libraries"
$model = Join-Path $pythonDir "model.txt"
$dll = Join-Path $root "cpp_dll\x64\Release\ai_engine.dll"

New-Item -ItemType Directory -Force -Path $mt5Files, $mt5Libraries | Out-Null

$python = Get-Command python.exe -ErrorAction SilentlyContinue
$pythonArgs = @()
if ($python) {
    $pythonExe = $python.Source
} else {
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if (-not $py) {
        throw "Python not found. Install Python 3 or add python.exe to PATH."
    }
    $pythonExe = $py.Source
    $pythonArgs = @("-3")
}

Push-Location $pythonDir
try {
    if ($Csv) {
        & $pythonExe @pythonArgs train.py --input $Csv --output $model
    } else {
        & $pythonExe @pythonArgs train.py --output $model
    }
}
finally {
    Pop-Location
}

Copy-Item -Force $model (Join-Path $mt5Files "model.txt")

if (-not $SkipCppBuild) {
    & (Join-Path $PSScriptRoot "build_cpp.ps1")
}

if (Test-Path $dll) {
    Copy-Item -Force $dll (Join-Path $mt5Libraries "ai_engine.dll")
} else {
    Write-Warning "DLL not found at $dll. Build it in Visual Studio, then copy it to mt5\Libraries."
}

Write-Host "Deploy done."
Write-Host "EA:      $root\mt5\Experts\BotVang_V8.mq5"
Write-Host "Model:   $root\mt5\Files\model.txt"
Write-Host "DLL:     $root\mt5\Libraries\ai_engine.dll"
