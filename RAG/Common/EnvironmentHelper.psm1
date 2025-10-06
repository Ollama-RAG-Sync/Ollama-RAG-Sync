# Common environment variable helper module for Ollama-RAG-Sync
# Provides cross-platform functionality for getting and setting persistent environment variables

<#
.SYNOPSIS
    Gets an environment variable value with cross-platform support.

.DESCRIPTION
    Retrieves environment variable values consistently across Windows, Linux, and Mac.
    On Windows, checks User scope, then Process scope, then Machine scope.
    On Linux/Mac, checks Process scope (which includes shell profile variables).

.PARAMETER Name
    The name of the environment variable to retrieve.

.PARAMETER DefaultValue
    Optional default value to return if the environment variable is not set.

.EXAMPLE
    Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH"

.EXAMPLE
    Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_URL" -DefaultValue "http://localhost:11434"
#>
function Get-CrossPlatformEnvVar {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [string]$DefaultValue = $null
    )
    
    # Try to get from current process environment (works on all platforms)
    $value = [System.Environment]::GetEnvironmentVariable($Name, "Process")
    
    # On Windows, also check User and Machine scopes
    if ($null -eq $value -and $IsWindows) {
        $value = [System.Environment]::GetEnvironmentVariable($Name, "User")
        if ($null -eq $value) {
            $value = [System.Environment]::GetEnvironmentVariable($Name, "Machine")
        }
    }
    
    # Return the value or default
    if ($null -eq $value) {
        return $DefaultValue
    }
    
    return $value
}

<#
.SYNOPSIS
    Sets an environment variable with cross-platform persistence.

.DESCRIPTION
    Sets environment variables with appropriate persistence for the platform.
    On Windows: Sets in User scope (persists across sessions).
    On Linux/Mac: Sets in current process AND attempts to persist in shell profile.

.PARAMETER Name
    The name of the environment variable to set.

.PARAMETER Value
    The value to set for the environment variable.

.PARAMETER Persist
    Whether to persist the variable (default: $true on Windows, advisory on Linux/Mac).

.EXAMPLE
    Set-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH" -Value "/opt/ollama-rag"

.NOTES
    On Linux/Mac, this function will update the current process environment immediately,
    but persistence requires manually sourcing the profile or starting a new shell.
    The function will output instructions for the user.
#>
function Set-CrossPlatformEnvVar {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,
        
        [Parameter(Mandatory = $false)]
        [bool]$Persist = $true
    )
    
    # Set in current process (works on all platforms)
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    
    if ($Persist) {
        if ($IsWindows) {
            # On Windows, set in User scope for persistence
            try {
                [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
                Write-Verbose "Environment variable '$Name' set in User scope (Windows)"
            }
            catch {
                Write-Warning "Failed to persist environment variable '$Name' to User scope: $_"
            }
        }
        else {
            # On Linux/Mac, attempt to update shell profile
            try {
                $profilePath = $null
                $exportLine = "export $Name=`"$Value`""
                
                # Determine which shell profile to use
                if (Test-Path "~/.bashrc") {
                    $profilePath = "~/.bashrc"
                }
                elseif (Test-Path "~/.bash_profile") {
                    $profilePath = "~/.bash_profile"
                }
                elseif (Test-Path "~/.zshrc") {
                    $profilePath = "~/.zshrc"
                }
                elseif (Test-Path "~/.profile") {
                    $profilePath = "~/.profile"
                }
                
                if ($profilePath) {
                    # Resolve the actual path
                    $resolvedPath = Resolve-Path $profilePath -ErrorAction Stop
                    
                    # Check if the variable is already set in the profile
                    $profileContent = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop
                    $pattern = "^\s*export\s+$Name\s*="
                    
                    if ($profileContent -match $pattern) {
                        # Replace existing line
                        $updatedContent = $profileContent -replace "(?m)$pattern.*$", $exportLine
                        Set-Content -Path $resolvedPath -Value $updatedContent -NoNewline
                        Write-Verbose "Updated environment variable '$Name' in $profilePath"
                    }
                    else {
                        # Append new line
                        Add-Content -Path $resolvedPath -Value "`n$exportLine"
                        Write-Verbose "Added environment variable '$Name' to $profilePath"
                    }
                    
                    Write-Warning "Environment variable '$Name' has been added to $profilePath"
                    Write-Warning "Run 'source $profilePath' or start a new shell session to load the variable."
                }
                else {
                    Write-Warning "Could not find a shell profile file (~/.bashrc, ~/.bash_profile, ~/.zshrc, or ~/.profile)"
                    Write-Warning "Please manually add the following line to your shell profile:"
                    Write-Warning "  $exportLine"
                }
            }
            catch {
                Write-Warning "Failed to persist environment variable '$Name' to shell profile: $_"
                Write-Warning "Please manually add the following line to your shell profile:"
                Write-Warning "  export $Name=`"$Value`""
            }
        }
    }
}

<#
.SYNOPSIS
    Removes an environment variable with cross-platform support.

.DESCRIPTION
    Removes environment variables with appropriate cleanup for the platform.
    On Windows: Removes from User scope.
    On Linux/Mac: Removes from current process and attempts to remove from shell profile.

.PARAMETER Name
    The name of the environment variable to remove.

.EXAMPLE
    Remove-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH"
#>
function Remove-CrossPlatformEnvVar {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    
    # Remove from current process
    [System.Environment]::SetEnvironmentVariable($Name, $null, "Process")
    
    if ($IsWindows) {
        # On Windows, remove from User scope
        try {
            [System.Environment]::SetEnvironmentVariable($Name, $null, "User")
            Write-Verbose "Environment variable '$Name' removed from User scope (Windows)"
        }
        catch {
            Write-Warning "Failed to remove environment variable '$Name' from User scope: $_"
        }
    }
    else {
        # On Linux/Mac, attempt to remove from shell profile
        try {
            $profilePath = $null
            
            # Determine which shell profile to use
            if (Test-Path "~/.bashrc") {
                $profilePath = "~/.bashrc"
            }
            elseif (Test-Path "~/.bash_profile") {
                $profilePath = "~/.bash_profile"
            }
            elseif (Test-Path "~/.zshrc") {
                $profilePath = "~/.zshrc"
            }
            elseif (Test-Path "~/.profile") {
                $profilePath = "~/.profile"
            }
            
            if ($profilePath) {
                # Resolve the actual path
                $resolvedPath = Resolve-Path $profilePath -ErrorAction Stop
                
                # Remove the line from the profile
                $profileContent = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop
                $pattern = "(?m)^\s*export\s+$Name\s*=.*$\r?\n?"
                
                if ($profileContent -match $pattern) {
                    $updatedContent = $profileContent -replace $pattern, ""
                    Set-Content -Path $resolvedPath -Value $updatedContent -NoNewline
                    Write-Verbose "Removed environment variable '$Name' from $profilePath"
                    Write-Warning "Run 'source $profilePath' or start a new shell session to apply the changes."
                }
            }
        }
        catch {
            Write-Warning "Failed to remove environment variable '$Name' from shell profile: $_"
        }
    }
}

<#
.SYNOPSIS
    Tests if the current platform is Windows.

.DESCRIPTION
    Returns $true if running on Windows, $false otherwise.
    Uses the built-in $IsWindows automatic variable if available (PowerShell 6+),
    or falls back to environment detection for PowerShell 5.1.

.EXAMPLE
    if (Test-IsWindows) { Write-Host "Running on Windows" }
#>
function Test-IsWindows {
    # PowerShell 6+ has automatic variables
    if ($null -ne (Get-Variable -Name "IsWindows" -ErrorAction SilentlyContinue)) {
        return $IsWindows
    }
    
    # PowerShell 5.1 fallback - check if we're on Windows
    return ([System.Environment]::OSVersion.Platform -eq "Win32NT")
}

# Export functions
Export-ModuleMember -Function Get-CrossPlatformEnvVar, Set-CrossPlatformEnvVar, Remove-CrossPlatformEnvVar, Test-IsWindows
