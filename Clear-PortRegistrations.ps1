<#
.SYNOPSIS
    Removes all port registrations for specified ports.

.DESCRIPTION
    This PowerShell script identifies and removes URL reservations for specified TCP ports
    using the 'netsh' command. It requires administrator privileges to run.

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
    Write-Host "Checking port $port..." -ForegroundColor Yellow
    
    if (Test-PortReservation -Port $port) {
        $reservations = Get-PortReservations -Port $port
        
        foreach ($url in $reservations) {
            Write-Host "Removing reservation for: $url" -ForegroundColor Cyan
            $result = netsh http delete urlacl url=$url
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Successfully removed reservation for $url" -ForegroundColor Green
            } else {
                Write-Host "Failed to remove reservation for $url" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "No URL reservations found for port $port" -ForegroundColor Green
    }
}

Write-Host "`nPort cleanup completed." -ForegroundColor Green