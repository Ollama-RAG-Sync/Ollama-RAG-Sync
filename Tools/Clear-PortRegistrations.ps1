<#
.SYNOPSIS
    Finds processes listening on specified ports, optionally stops them, and removes URL reservations.

.DESCRIPTION
    This PowerShell script identifies processes listening on specified TCP ports, prompts the user
    to stop them, and then removes any associated 'netsh http' URL reservations for those ports.
    It requires administrator privileges to run.

.PARAMETER Ports
    An array of port numbers to clear registrations for.

.EXAMPLE
    .\Clear-PortRegistrations.ps1 -Ports 8080, 8082, 5000

.NOTES
    Must be run as Administrator.
#>

param(
    [Parameter(Mandatory=$true)]
    [int[]]$Ports
)

# Function to stop a process with confirmation
function Stop-ProcessWithConfirmation {
    param(
        [Parameter(Mandatory=$true)]
        [int]$ProcessId,
        [Parameter(Mandatory=$true)]
        [string]$ProcessName,
        [Parameter(Mandatory=$true)]
        [int]$Port
    )

    $confirmation = Read-Host "Process '$ProcessName' (PID: $ProcessId) is using port $Port. Stop it? (Y/N)"
    if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {
        try {
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
            Write-Host "Successfully stopped process '$ProcessName' (PID: $ProcessId)." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to stop process '$ProcessName' (PID: $ProcessId). Error: $($_.Exception.Message)"
        }
    } else {
        Write-Host "Skipping process '$ProcessName' (PID: $ProcessId)." -ForegroundColor Yellow
    }
}

# Check for admin privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges. Please restart PowerShell as an administrator."
    exit 1
}

# Function to check if a port has reservations
function Test-PortReservation {
    param([int]$Port)
    
    $reservations = netsh http show urlacl | Select-String -Pattern ":$Port"
    return $reservations.Count -gt 0
}

# Function to get all URL reservations for a specific port
function Get-PortReservations {
    param([int]$Port)
    
    $output = netsh http show urlacl | Select-String -Pattern ":$Port" -Context 0,1
    $reservations = @()
    
    foreach ($match in $output) {
        if ($match.Line -match 'Reserved URL\s+:\s+(.+)') {
            $reservations += $matches[1]
        }
    }
    
    return $reservations
}

# Main script logic
foreach ($port in $Ports) {
    Write-Host "--- Processing Port $port ---" -ForegroundColor Magenta

    # Find processes listening on the port
    try {
        $connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop
        if ($connections) {
            foreach ($connection in $connections) {
                $processId = $connection.OwningProcess
                try {
                    $process = Get-Process -Id $processId -ErrorAction Stop
                    Write-Host "Found process listening on port $port :" -ForegroundColor Cyan
                    Write-Host "  PID      : $processId"
                    Write-Host "  Name     : $($process.ProcessName)"
                    Write-Host "  Path     : $($process.Path)"
                    
                    # Ask for confirmation and stop the process
                    Stop-ProcessWithConfirmation -ProcessId $processId -ProcessName $process.ProcessName -Port $port

                } catch {
                    Write-Warning "Could not retrieve details for process PID $processId using port $port. It might have already exited. Error: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Host "No processes found listening on port $port." -ForegroundColor Green
        }
    } catch {
         Write-Warning "Could not check for processes on port $port. Error: $($_.Exception.Message)"
    }

    # Check and remove URL reservations
    Write-Host "Checking for URL reservations on port $port..." -ForegroundColor Yellow
    if (Test-PortReservation -Port $port) {
        $reservations = Get-PortReservations -Port $port
        
        foreach ($url in $reservations) {
            Write-Host "Attempting to remove reservation for: $url" -ForegroundColor Cyan
            netsh http delete urlacl url=$url | Out-Null # Suppress netsh output unless error
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Successfully removed reservation for $url" -ForegroundColor Green
            } else {
                # Get more detailed error if possible
                $errorOutput = $(netsh http delete urlacl url=$url 2>&1) 
                Write-Warning "Failed to remove reservation for $url. Netsh exit code: $LASTEXITCODE. Output: $errorOutput"
            }
        }
    } else {
        Write-Host "No URL reservations found for port $port." -ForegroundColor Green
    }
    Write-Host "---------------------------`n" -ForegroundColor Magenta
}

Write-Host "Port processing completed." -ForegroundColor Green
