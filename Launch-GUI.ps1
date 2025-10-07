# Launch Ollama-RAG-Sync GUI
# This PowerShell script launches the GUI application

param(
    [Parameter(Mandatory=$false)]
    [string]$PythonCommand = "python"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Ollama-RAG-Sync Control Center Launcher" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GuiDir = Join-Path -Path $ScriptDir -ChildPath "GUI"
$LaunchScript = Join-Path -Path $GuiDir -ChildPath "launch_gui.py"

# Check if Python is available
try {
    $pythonVersion = & $PythonCommand --version 2>&1
    Write-Host "✓ Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ Python not found!" -ForegroundColor Red
    Write-Host "  Please install Python 3.8 or higher" -ForegroundColor Yellow
    Write-Host "  Download from: https://www.python.org/downloads/" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Check if GUI directory exists
if (-not (Test-Path $GuiDir)) {
    Write-Host "✗ GUI directory not found: $GuiDir" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Check if launch script exists
if (-not (Test-Path $LaunchScript)) {
    Write-Host "✗ Launch script not found: $LaunchScript" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "✓ GUI files found" -ForegroundColor Green
Write-Host ""

# Check for required packages
Write-Host "Checking Python dependencies..." -ForegroundColor Cyan
$packagesOk = $true

try {
    & $PythonCommand -c "import PyQt6" 2>$null
    Write-Host "✓ PyQt6 installed" -ForegroundColor Green
} catch {
    Write-Host "✗ PyQt6 not installed" -ForegroundColor Yellow
    $packagesOk = $false
}

try {
    & $PythonCommand -c "import requests" 2>$null
    Write-Host "✓ requests installed" -ForegroundColor Green
} catch {
    Write-Host "✗ requests not installed" -ForegroundColor Yellow
    $packagesOk = $false
}

if (-not $packagesOk) {
    Write-Host ""
    Write-Host "Some dependencies are missing." -ForegroundColor Yellow
    $install = Read-Host "Would you like to install them now? (y/n)"
    
    if ($install -eq 'y' -or $install -eq 'Y') {
        Write-Host ""
        Write-Host "Installing requirements..." -ForegroundColor Cyan
        $requirementsFile = Join-Path -Path $ScriptDir -ChildPath "RAG\requirements.txt"
        
        if (Test-Path $requirementsFile) {
            & $PythonCommand -m pip install -r $requirementsFile
            Write-Host ""
            Write-Host "✓ Dependencies installed" -ForegroundColor Green
        } else {
            Write-Host "Requirements file not found. Installing manually..." -ForegroundColor Yellow
            & $PythonCommand -m pip install PyQt6 requests
        }
    } else {
        Write-Host ""
        Write-Host "Please install the required packages manually:" -ForegroundColor Yellow
        Write-Host "  pip install PyQt6 requests" -ForegroundColor White
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Starting GUI Application" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Launch the GUI
try {
    Set-Location $GuiDir
    & $PythonCommand $LaunchScript
} catch {
    Write-Host ""
    Write-Host "✗ Failed to launch GUI: $_" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
