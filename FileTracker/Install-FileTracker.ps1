<#
.SYNOPSIS
    Downloads and installs the SQLite assemblies for use with PowerShell.
.DESCRIPTION
    This script downloads the required NuGet packages for SQLite, extracts them, and copies
    the necessary DLLs to the specified installation directory under a .ai/libs folder.
    
    Packages installed:
    - Microsoft.Data.Sqlite.Core
    - SQLitePCLRaw.core
    - SQLitePCLRaw.provider.e_sqlite3
    - SQLitePCLRaw.lib.e_sqlite3
.PARAMETER FolderPath
    The base folder where the .ai/libs directories will be created and assemblies installed.
.PARAMETER Force
    If specified, forces the installation by closing handles to any DLLs that might be in use.
.EXAMPLE
    .\Install-FileTracker.ps1 -FolderPath "C:\MyProject"
.EXAMPLE
    .\Install-FileTracker.ps1 -FolderPath "C:\MyProject" -Force
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Configuration - all required packages and their file paths
$packages = @(
    @{
        Name = "Microsoft.Data.Sqlite.Core"
        Version = "9.0.3"
        SourcePath = "lib/net8.0/Microsoft.Data.Sqlite.dll"
        TargetFile = "Microsoft.Data.Sqlite.dll"
    },
    @{
        Name = "SQLitePCLRaw.core"
        Version = "2.1.10"
        SourcePath = "lib/netstandard2.0/SQLitePCLRaw.core.dll"
        TargetFile = "SQLitePCLRaw.core.dll"
    },
    @{
        Name = "SQLitePCLRaw.provider.e_sqlite3"
        Version = "2.1.11"
        SourcePath = "lib/netstandard2.0/SQLitePCLRaw.provider.e_sqlite3.dll"
        TargetFile = "SQLitePCLRaw.provider.e_sqlite3.dll"
    },
    @{
        Name = "SQLitePCLRaw.lib.e_sqlite3"
        Version = "2.1.11"
        SourcePath = "runtimes/win-x64/native/e_sqlite3.dll"
        TargetFile = "e_sqlite3.dll"
    }
)

# Setup paths
$libs = Join-Path -Path $InstallPath -ChildPath "libs"
$tempFolder = Join-Path -Path $InstallPath -ChildPath "temp"
$handleExe = Join-Path -Path $InstallPath -ChildPath "handle.exe"

function Allow-FileWrite {
    param (
        [string]$Dir
    )
    # If you need to set specific permissions to ensure it's writable
    $acl = Get-Acl -Path $Dir
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $permission = "$currentUser","FullControl","Allow"
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
    $acl.SetAccessRule($accessRule)
    $acl | Set-Acl -Path $Dir

    & attrib.exe -R $Dir /S /D
}

function Initialize-Directories {
    param (
        [string]$AiDir,
        [string]$LibsDir
    )
    
    # Create .ai folder if it doesn't exist
    if (-not (Test-Path -Path $AiDir)) {
        try {
            New-Item -Path $AiDir -ItemType Directory -ErrorAction Stop
            Allow-FileWrite -Dir $AiDir
            Write-Host "Created .ai folder at $AiDir" -ForegroundColor Yellow
        }
        catch {
            Write-Error "Failed to create directory $AiDir : $_"
            exit 1
        }
    }
    
    # Create libs folder if it doesn't exist
    if (-not (Test-Path -Path $LibsDir)) {
        try {
            New-Item -Path $LibsDir -ItemType Directory -ErrorAction Stop
            Allow-FileWrite -Dir $LibsDir
            Write-Host "Created libs folder at $LibsDir" -ForegroundColor Yellow
        }
        catch {
            Write-Error "Failed to create directory $LibsDir : $_"
            exit 1
        }
    }
}

function Download-HandleExe {
    param (
        [string]$TargetPath
    )
    
    try {
        # Create directory if it doesn't exist
        $targetDir = Split-Path -Path $TargetPath -Parent
        if (-not (Test-Path -Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }
        
        # Check if handle.exe already exists
        if (Test-Path -Path $TargetPath) {
            Write-Host "handle.exe already exists at $TargetPath" -ForegroundColor Yellow
            return $true
        }
        
        # Download handle.exe from Sysinternals
        Write-Host "Downloading Sysinternals handle.exe..." -ForegroundColor Cyan
        $handleZip = Join-Path -Path $env:TEMP -ChildPath "handle.zip"
        Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Handle.zip" -OutFile $handleZip -ErrorAction Stop
        
        # Create a temporary directory for extraction
        $extractDir = Join-Path -Path $env:TEMP -ChildPath "HandleExtract"
        if (Test-Path -Path $extractDir) {
            $null = Remove-Item -Path $extractDir -Recurse -Force
        }
        New-Item -Path $extractDir -ItemType Directory | Out-Null
        
        # Extract the zip file
        Write-Host "Extracting handle.exe..." -ForegroundColor Cyan
        Expand-Archive -Path $handleZip -DestinationPath $extractDir -Force
        
        # Copy handle.exe to the target location
        Write-Host "Installing handle.exe to $TargetPath..." -ForegroundColor Cyan
        Copy-Item -Path (Join-Path -Path $extractDir -ChildPath "handle.exe") -Destination $TargetPath -Force
        
        # Copy EULA.txt if it exists
        $eulaSrc = Join-Path -Path $extractDir -ChildPath "Eula.txt"
        if (Test-Path -Path $eulaSrc) {
            Copy-Item -Path $eulaSrc -Destination (Join-Path -Path $targetDir -ChildPath "Eula.txt") -Force
        }
        
        # Clean up
        $null = Remove-Item -Path $handleZip -Force -ErrorAction SilentlyContinue
        $null = Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        
        if (Test-Path -Path $TargetPath) {
            Write-Host "Successfully installed handle.exe" -ForegroundColor Green
            return $true
        }
        else {
            Write-Error "Failed to install handle.exe"
            return $false
        }
    }
    catch {
        Write-Error "Error downloading handle.exe: $_"
        return $false
    }
}

function Get-ProcessesWithHandles {
    param (
        [string]$FilePath
    )
    
    $processes = @()
    
    if (Test-Path -Path $handleExe) {
        try {
            Write-Host "Using handle.exe to find processes with open handles to $FilePath..." -ForegroundColor Yellow
            $outputFile = Join-Path -Path $installFolder -ChildPath "handles_output.txt"
            $outputErrFile = Join-Path -Path $installFolder -ChildPath "handles_output.err.txt"
            $handleProcess = Start-Process -FilePath $handleExe -ArgumentList $FilePath, "-nobanner" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError $outputErrFile
            Start-Sleep -Seconds 5
            
            # Check if process is still running and terminate it if it is
            if (-not $handleProcess.HasExited) {
                Stop-Process -Id $handleProcess.Id -Force -ErrorAction SilentlyContinue
            }
            
            $handleOutput = Get-Content -Path $outputFile -ErrorAction SilentlyContinue
            $null = Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue
            Write-Host "Finished finding handles to $FilePath..." -ForegroundColor Cyan
            foreach ($line in $handleOutput) {
                if ($line -match "pid: (\d+)") {
                    $processId = $Matches[1]
                    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                    if ($process) {
                        $processes += $process
                    }
                }
            }
            $null = Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue 
            $null = Remove-Item -Path $outputErrFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Error using handle.exe: $_"
        }
    }
    else {
        Write-Warning "handle.exe not found at expected location: $handleExe"
    }
    
    # Fallback method if handle.exe didn't find any processes
    if ($processes.Count -eq 0) {
        Write-Host "Using alternative method to find processes..." -ForegroundColor Yellow
        $fileName = Split-Path -Path $FilePath -Leaf
        
        Get-Process | ForEach-Object {
            $process = $_
            try {
                $process.Modules | Where-Object { $_.FileName -eq $fileName } | ForEach-Object {
                    if ($processes -notcontains $process) {
                        $processes += $process
                    }
                }
            }
            catch {
                # Ignore processes we can't access
            }
        }
    }
    
    return $processes
}

function Install-Package {
    param (
        [hashtable]$Package
    )
    
    $packageName = $Package.Name
    $packageVersion = $Package.Version
    $sourceFilePath = $Package.SourcePath
    $targetFileName = $Package.TargetFile
    
    $nugetUrl = "https://www.nuget.org/api/v2/package/$packageName/$packageVersion"
    $tempFile = Join-Path -Path $env:TEMP -ChildPath "$packageName.nupkg"
    $targetFilePath = Join-Path -Path $installFolder -ChildPath $targetFileName
    
    try {
        # Check if file already exists and is valid
        if (Test-Path -Path $targetFilePath) {
            if (-not $Force) {
                Write-Host "$targetFileName already exists. Skipping download." -ForegroundColor Green
                return $true
            } else {
                Write-Host "$targetFileName already exists but Force flag is enabled. Will reinstall." -ForegroundColor Yellow
            }
        }
        
        # Download package
        Write-Host "Downloading $packageName v$packageVersion..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $nugetUrl -OutFile $tempFile -ErrorAction Stop
        
        # Extract package
        Write-Host "Extracting $packageName..." -ForegroundColor Cyan
        if (Test-Path -Path $tempFolder) {
            $null = Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction Stop
        }
        Expand-Archive -Path $tempFile -DestinationPath $tempFolder -Force -ErrorAction Stop
        
        # Try to copy the file
        $sourcePath = Join-Path -Path $tempFolder -ChildPath $sourceFilePath
        
        # Check if the target file exists and is locked
        if (Test-Path -Path $targetFilePath) {
            # If Force is enabled, try to close any processes holding handles to the file
            if ($Force) {
                Write-Host "Checking for processes with handles to $targetFileName..." -ForegroundColor Yellow
                $processes = Get-ProcessesWithHandles -FilePath $targetFilePath
                
                foreach ($process in $processes) {
                    try {
                        Write-Host "Closing process $($process.Name) (PID: $($process.Id)) that has a handle on $targetFileName" -ForegroundColor Yellow
                        $process.Kill()
                        $process.WaitForExit(5000)
                    }
                    catch {
                        Write-Warning "Failed to close process $($process.Name) (PID: $($process.Id)): $_"
                    }
                }
            }
        }
        
        # Attempt to copy the file
        Write-Host "Installing $targetFileName..." -ForegroundColor Cyan
        
        # Create parent directory if it doesn't exist
        $targetDir = Split-Path -Path $targetFilePath -Parent
        if (-not (Test-Path -Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }
        
        try {
            Copy-Item -Path $sourcePath -Destination $targetFilePath -Force -ErrorAction Stop
        }
        catch {
            if ($Force) {
                Write-Host "Standard copy failed, trying alternative methods..." -ForegroundColor Yellow
                
                # Try .NET File copy
                try {
                    [System.IO.File]::Copy($sourcePath, $targetFilePath, $true)
                }
                catch {
                    # Try robocopy as a last resort
                    $robocopyArgs = @(
                        """$(Split-Path -Path $sourcePath -Parent)"""
                        """$(Split-Path -Path $targetFilePath -Parent)"""
                        """$(Split-Path -Path $sourcePath -Leaf)"""
                        "/R:0"
                        "/W:0"
                    )
                    
                    Write-Host "Using robocopy as a last resort..." -ForegroundColor Yellow
                    $robocopyOutput = & robocopy $robocopyArgs
                    
                    # Check if robocopy actually copied the file
                    if (-not (Test-Path -Path $targetFilePath)) {
                        throw "Failed to copy file using robocopy"
                    }
                }
            }
            else {
                throw "Failed to copy file. Use -Force to attempt to close handles and force copy: $_"
            }
        }
        
        Write-Host "$targetFileName installed successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to install $packageName v$packageVersion : $_"
        return $false
    }
    finally {
        # Clean up the NuGet package file
        if (Test-Path -Path $tempFile) {
            $null = Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Check-AllDllsExist {
    $allExist = $true
    foreach ($package in $packages) {
        $targetFilePath = Join-Path -Path $installFolder -ChildPath $package.TargetFile
        if (-not (Test-Path -Path $targetFilePath)) {
            $allExist = $false
            break
        }
    }
    return $allExist
}

# Main execution
try {
    # Create required directories
    Initialize-Directories -AiDir $aiFolder -LibsDir $installFolder
    
    # Check if all DLLs already exist and we're not forcing reinstall
    $allDllsExist = Check-AllDllsExist
    if ($allDllsExist -and -not $Force) {
        Write-Host "All SQLite assemblies are already installed. Use -Force to reinstall." -ForegroundColor Green
        Write-Host "Installation directory: $installFolder"
        exit 0
    }
    
    # Download handle.exe (only needed if we have to close handles)
    if ($Force) {
        Write-Host "Ensuring handle.exe is available..."
        Download-HandleExe -TargetPath $handleExe | Out-Null
    }
    
    # Track installation success
    $successCount = 0
    $totalPackages = $packages.Count
    
    # Install each package
    foreach ($package in $packages) {
        if (Install-Package -Package $package) {
            $successCount++
        }
    }
    
    # Clean up temp folder
    if (Test-Path -Path $tempFolder) {
       $null = Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Report results
    if ($successCount -eq $totalPackages) {
        Write-Host "SQLite assemblies installed successfully ($successCount/$totalPackages)."
        Write-Host "Installation directory: $installFolder" -ForegroundColor Cyan
    }
    else {
        Write-Host "SQLite assembly installation partially completed ($successCount/$totalPackages)."
    }
}
catch {
    Write-Error "An unexpected error occurred: $_"
    exit 1
}
