# Cross-Platform Setup Guide

This document explains how to set up and use Ollama-RAG-Sync on Windows, Linux, and macOS.

## Overview

Ollama-RAG-Sync now supports cross-platform operation with automatic environment variable management. The system uses a custom `EnvironmentHelper` module to handle platform differences transparently.

## Environment Variables

The following environment variables are used by the system:

| Variable Name | Description | Default Value |
|--------------|-------------|---------------|
| `OLLAMA_RAG_INSTALL_PATH` | Installation directory for databases and files | (Required - no default) |
| `OLLAMA_RAG_EMBEDDING_MODEL` | Ollama embedding model to use | `mxbai-embed-large:latest` |
| `OLLAMA_RAG_URL` | Ollama API base URL | `http://localhost:11434` |
| `OLLAMA_RAG_CHUNK_SIZE` | Number of lines per text chunk | `20` |
| `OLLAMA_RAG_CHUNK_OVERLAP` | Number of overlapping lines between chunks | `2` |
| `OLLAMA_RAG_FILE_TRACKER_API_PORT` | Port for FileTracker API | `10003` |
| `OLLAMA_RAG_VECTORS_API_PORT` | Port for Vectors API | `10001` |
| `OLLAMA_RAG_LOG_LEVEL` | Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL) | `INFO` |
| `OLLAMA_RAG_LOG_FILE` | Optional log file path | (None - logs to console only) |

## Platform-Specific Setup

### Windows

On Windows, environment variables are stored in the Windows Registry and persist across sessions automatically.

#### Automatic Setup (Recommended)

Run the setup script which will automatically configure environment variables:

```powershell
.\RAG\Setup-RAG.ps1 -InstallPath "C:\RAG" -EmbeddingModel "mxbai-embed-large:latest"
```

The setup script will:
- Create the installation directory
- Set environment variables in User scope
- Install required dependencies
- Initialize databases

#### Manual Setup

If you need to manually set environment variables:

```powershell
# Set environment variable (persists across sessions)
[System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "C:\RAG", "User")

# Or use the cross-platform helper
Import-Module .\RAG\Common\EnvironmentHelper.psm1
Set-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH" -Value "C:\RAG"
```

#### Verify Environment Variables

```powershell
# View current environment variable
$env:OLLAMA_RAG_INSTALL_PATH

# Or use the helper
Import-Module .\RAG\Common\EnvironmentHelper.psm1
Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH"
```

### Linux and macOS

On Linux and macOS, environment variables are stored in shell profile files for persistence.

#### Automatic Setup (Recommended)

Run the setup script which will automatically configure environment variables:

```bash
pwsh ./RAG/Setup-RAG.ps1 -InstallPath "/opt/ollama-rag" -EmbeddingModel "mxbai-embed-large:latest"
```

The setup script will:
- Create the installation directory
- Add environment variables to your shell profile (`~/.bashrc`, `~/.bash_profile`, `~/.zshrc`, or `~/.profile`)
- Install required dependencies
- Initialize databases

**Important:** After running the setup script, you must either:
- Source your shell profile: `source ~/.bashrc` (or your profile file)
- Start a new terminal session

The script will display instructions for which file was updated.

#### Manual Setup

If you need to manually set environment variables:

##### Option 1: Using PowerShell and the Helper Module

```bash
pwsh
```

```powershell
Import-Module ./RAG/Common/EnvironmentHelper.psm1
Set-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH" -Value "/opt/ollama-rag"
```

This will automatically update your shell profile.

##### Option 2: Directly Edit Shell Profile

Edit your shell profile file (e.g., `~/.bashrc` for Bash or `~/.zshrc` for Zsh):

```bash
# Add to ~/.bashrc or ~/.zshrc
export OLLAMA_RAG_INSTALL_PATH="/opt/ollama-rag"
export OLLAMA_RAG_EMBEDDING_MODEL="mxbai-embed-large:latest"
export OLLAMA_RAG_URL="http://localhost:11434"
export OLLAMA_RAG_CHUNK_SIZE="20"
export OLLAMA_RAG_CHUNK_OVERLAP="2"
export OLLAMA_RAG_FILE_TRACKER_API_PORT="10003"
export OLLAMA_RAG_VECTORS_API_PORT="10001"
```

Then reload the profile:

```bash
source ~/.bashrc  # or ~/.zshrc
```

#### Verify Environment Variables

```bash
# In bash/zsh
echo $OLLAMA_RAG_INSTALL_PATH

# Or in PowerShell
pwsh -c '$env:OLLAMA_RAG_INSTALL_PATH'

# Or use the helper
pwsh
Import-Module ./RAG/Common/EnvironmentHelper.psm1
Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH"
```

## Installation Path Recommendations

### Windows
```
C:\RAG
C:\Users\<username>\Documents\RAG
C:\ProgramData\OllamaRAG
```

### Linux
```
/opt/ollama-rag
/home/<username>/.local/share/ollama-rag
/var/lib/ollama-rag (requires sudo)
```

### macOS
```
/opt/ollama-rag
/Users/<username>/Library/Application Support/ollama-rag
/Users/<username>/.local/share/ollama-rag
```

## Quick Start Guide

### 1. Install Prerequisites

#### All Platforms
- PowerShell 7.0 or later ([Download](https://github.com/PowerShell/PowerShell/releases))
- Python 3.8 or later ([Download](https://www.python.org/downloads/))
- Ollama ([Download](https://ollama.ai))

### 2. Clone the Repository

```bash
git clone https://github.com/YourUsername/Ollama-RAG-Sync.git
cd Ollama-RAG-Sync
```

### 3. Run Setup

#### Windows (PowerShell)
```powershell
.\RAG\Setup-RAG.ps1 -InstallPath "C:\RAG"
```

#### Linux/macOS (PowerShell)
```bash
pwsh ./RAG/Setup-RAG.ps1 -InstallPath "/opt/ollama-rag"
```

**Note:** On Linux/macOS, remember to source your shell profile after setup:
```bash
source ~/.bashrc  # or ~/.zshrc, ~/.bash_profile, etc.
```

### 4. Start the System

#### Windows
```powershell
.\RAG\Start-RAG.ps1
```

#### Linux/macOS
```bash
pwsh ./RAG/Start-RAG.ps1
```

### 5. Add a Collection

#### Windows
```powershell
.\RAG\FileTracker\Add-Folder.ps1 -CollectionName "MyDocs" -FolderPath "C:\Documents"
```

#### Linux/macOS
```bash
pwsh ./RAG/FileTracker/Add-Folder.ps1 -CollectionName "MyDocs" -FolderPath "/home/user/documents"
```

### 6. Process Documents

#### Windows
```powershell
.\RAG\Processor\Process-Collection.ps1 -CollectionName "MyDocs"
```

#### Linux/macOS
```bash
pwsh ./RAG/Processor/Process-Collection.ps1 -CollectionName "MyDocs"
```

## Troubleshooting

### Environment Variables Not Persisting (Linux/macOS)

If environment variables are not available after restarting your terminal:

1. Check which shell you're using:
   ```bash
   echo $SHELL
   ```

2. Verify the correct profile file was updated:
   - Bash: `~/.bashrc` or `~/.bash_profile`
   - Zsh: `~/.zshrc`
   - Generic: `~/.profile`

3. Manually check the profile file:
   ```bash
   grep OLLAMA_RAG ~/.bashrc
   ```

4. If needed, manually add the exports and source the file:
   ```bash
   source ~/.bashrc
   ```

### PowerShell Not Found (Linux/macOS)

Install PowerShell:

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y powershell
```

#### macOS (using Homebrew)
```bash
brew install --cask powershell
```

#### Other Linux distributions
See [PowerShell installation guide](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell)

### Permission Denied Errors (Linux/macOS)

If you get permission errors when creating directories:

1. Use a directory in your home folder:
   ```bash
   pwsh ./RAG/Setup-RAG.ps1 -InstallPath "$HOME/.local/share/ollama-rag"
   ```

2. Or use sudo for system-wide installation:
   ```bash
   sudo pwsh ./RAG/Setup-RAG.ps1 -InstallPath "/opt/ollama-rag"
   ```

### Database File Permissions

If you encounter SQLite database permission issues on Linux/macOS:

```bash
# Fix permissions on the installation directory
chmod -R u+rw /opt/ollama-rag
```

## Advanced Configuration

### Using Custom Environment Variables

You can override defaults by setting environment variables before running scripts:

#### Windows
```powershell
$env:OLLAMA_RAG_CHUNK_SIZE = "30"
.\RAG\Start-RAG.ps1
```

#### Linux/macOS
```bash
export OLLAMA_RAG_CHUNK_SIZE="30"
pwsh ./RAG/Start-RAG.ps1
```

### Temporary Override (Single Session)

To temporarily use different settings without changing persistent environment variables:

```powershell
.\RAG\Start-RAG.ps1 -InstallPath "C:\CustomPath" -ChunkSize 30
```

This works on all platforms.

## Developer Notes

### Cross-Platform Environment Helper API

The `EnvironmentHelper.psm1` module provides these functions:

```powershell
# Get an environment variable (checks User scope on Windows, Process on all platforms)
Get-CrossPlatformEnvVar -Name "VAR_NAME" -DefaultValue "default"

# Set an environment variable (persists to User Registry on Windows, shell profile on Linux/Mac)
Set-CrossPlatformEnvVar -Name "VAR_NAME" -Value "value"

# Remove an environment variable
Remove-CrossPlatformEnvVar -Name "VAR_NAME"

# Check if running on Windows
Test-IsWindows
```

### How It Works

#### Windows
- Uses `[System.Environment]::GetEnvironmentVariable()` with "User" scope
- Variables stored in Registry: `HKEY_CURRENT_USER\Environment`
- Persists automatically across sessions

#### Linux/macOS
- Writes `export VAR_NAME="value"` to shell profile
- Auto-detects profile file: `~/.bashrc`, `~/.bash_profile`, `~/.zshrc`, or `~/.profile`
- User must source profile or start new shell to load changes

## Migration from Windows-Only Version

If you were using an earlier Windows-only version:

1. Your existing environment variables will continue to work on Windows
2. No changes needed - the new code is backward compatible
3. If moving to Linux/Mac, run Setup-RAG.ps1 on the new platform

## See Also

- [Architecture Documentation](./ARCHITECTURE.md)
- [Testing Guide](./TESTING.md)
- [Contributing Guidelines](./CONTRIBUTING.md)
