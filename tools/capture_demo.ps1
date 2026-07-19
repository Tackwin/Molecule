param(
    [int] $FrameRate = 60
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $repository "build"
$captureDirectory = Join-Path $buildDirectory "captures"
$controlScript = Join-Path $PSScriptRoot "molecule_control.ps1"
$gamePath = Join-Path $buildDirectory "Molecule.exe"
$totalFrames = 10 * $FrameRate

function Invoke-MoleculeControl {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Command)
    $response = & $controlScript @Command
    if ($LASTEXITCODE -ne 0) {
        throw "Molecule control command failed: $($Command -join ' ')"
    }
    return $response
}

function Wait-MoleculeStep {
    param([int] $FrameCount)
    Invoke-MoleculeControl step $FrameCount | Out-Null
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        $status = Invoke-MoleculeControl status
        if ($status -match "step_frames=(\d+)") {
            if ([int] $Matches[1] -eq 0) {
                return
            }
        }
        Start-Sleep -Milliseconds 5
    }
    throw "Timed out waiting for $FrameCount captured frames."
}

if (Get-Process Molecule -ErrorAction SilentlyContinue) {
    throw "Molecule is already running. Close it before starting the scripted capture."
}

New-Item -ItemType Directory -Force -Path $captureDirectory | Out-Null
Get-ChildItem -LiteralPath $captureDirectory -Filter "frame_*.qoi" -ErrorAction SilentlyContinue | Remove-Item -Force

$game = Start-Process -FilePath $gamePath -WorkingDirectory $buildDirectory -WindowStyle Hidden -PassThru
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            Invoke-MoleculeControl status | Out-Null
            break
        }
        catch {
            Start-Sleep -Milliseconds 100
        }
    }
    if ($game.HasExited) {
        throw "Molecule exited before the capture started."
    }

    Invoke-MoleculeControl pause | Out-Null
    Invoke-MoleculeControl capture start | Out-Null

    Wait-MoleculeStep 60

    Invoke-MoleculeControl key z down | Out-Null
    Wait-MoleculeStep 90
    Invoke-MoleculeControl key z up | Out-Null

    Invoke-MoleculeControl key d down | Out-Null
    Wait-MoleculeStep 90
    Invoke-MoleculeControl key d up | Out-Null

    Invoke-MoleculeControl wheel 4 | Out-Null
    Wait-MoleculeStep 60
    Invoke-MoleculeControl wheel -4 | Out-Null
    Wait-MoleculeStep 60

    Invoke-MoleculeControl key f8 down | Out-Null
    Wait-MoleculeStep 1
    Invoke-MoleculeControl key f8 up | Out-Null
    Wait-MoleculeStep 119

    Invoke-MoleculeControl key f8 down | Out-Null
    Wait-MoleculeStep 1
    Invoke-MoleculeControl key f8 up | Out-Null
    Wait-MoleculeStep 119

    Invoke-MoleculeControl capture stop | Out-Null

    $frames = Get-ChildItem -LiteralPath $captureDirectory -Filter "frame_*.qoi"
    if ($frames.Count -ne $totalFrames) {
        throw "Expected $totalFrames frames, found $($frames.Count)."
    }
    for ($index = 0; $index -lt $totalFrames; $index += 1) {
        if (-not (Test-Path -LiteralPath (Join-Path $captureDirectory "frame_$index.qoi"))) {
            throw "Missing captured frame $index."
        }
    }
    Write-Output "Captured $totalFrames deterministic frames in $captureDirectory"
}
finally {
    if (-not $game.HasExited) {
        try {
            Invoke-MoleculeControl capture stop | Out-Null
            Invoke-MoleculeControl quit | Out-Null
            if (-not $game.WaitForExit(5000)) {
                Stop-Process -Id $game.Id
            }
        }
        catch {
            Stop-Process -Id $game.Id -ErrorAction SilentlyContinue
        }
    }
}
