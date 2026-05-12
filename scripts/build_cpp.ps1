param(
    [string]$Configuration = "Release",
    [string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $root "cpp_dll\ai_engine.sln"

$processEnvironment = [System.Environment]::GetEnvironmentVariables("Process")
if ($processEnvironment.Contains("Path") -and $processEnvironment.Contains("PATH")) {
    [System.Environment]::SetEnvironmentVariable("PATH", $null, "Process")
    [System.Environment]::SetEnvironmentVariable("Path", $env:Path, "Process")
}

$msbuildCommand = Get-Command msbuild.exe -ErrorAction SilentlyContinue
if ($msbuildCommand) {
    $msbuildPath = $msbuildCommand.Source
} else {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $install = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
        $candidate = Join-Path $install "MSBuild\Current\Bin\MSBuild.exe"
        if (Test-Path $candidate) {
            $msbuildPath = $candidate
        }
    }
}

if (-not $msbuildPath) {
    throw "MSBuild not found. Install Visual Studio Build Tools with C++ workload."
}

& $msbuildPath $solution /p:Configuration=$Configuration /p:Platform=$Platform /m
