# Contributing Guide

Welcome to the Ollama-RAG-Sync project! This guide will help you contribute effectively.

## Getting Started

### Prerequisites

- PowerShell 7.0+
- .NET 8.0 SDK
- Python 3.8+
- Ollama (for full integration testing)
- Git

### Setup Development Environment

```powershell
# Clone the repository
git clone https://github.com/your-username/Ollama-RAG-Sync.git
cd Ollama-RAG-Sync

# Install PowerShell dependencies
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force
Install-Module -Name PSScriptAnalyzer -Force

# Install Python dependencies
pip install chromadb requests numpy

# Verify .NET installation
dotnet --version

# Run tests to verify setup
.\scripts\run-tests.ps1
```

## Development Workflow

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b bugfix/issue-description
```

### 2. Make Changes

Follow the project structure:
- PowerShell modules in `RAG/*/Modules/`
- PowerShell scripts in `RAG/*/Scripts/`
- .NET code organized in `MCP/src/`
- Tests adjacent to the code being tested

### 3. Write Tests

**Always write tests for new functionality!**

```powershell
# Create test file alongside your module
# Example: MyModule.psm1 → Tests/Unit/MyModule.Tests.ps1

Describe "MyModule Function" -Tag "Unit" {
    It "Should do something" {
        $result = My-Function -Input "test"
        $result | Should -Not -BeNullOrEmpty
    }
}
```

### 4. Run Tests

```powershell
# Run all tests
.\scripts\run-tests.ps1

# Run only your tests
Invoke-Pester -Path ".\RAG\YourComponent\Tests\"

# Run with coverage
.\scripts\run-tests.ps1 -GenerateCoverage
```

### 5. Check Code Quality

```powershell
# PowerShell code analysis
Invoke-ScriptAnalyzer -Path .\RAG -Recurse

# .NET formatting
dotnet format MCP/Ollama-RAG-Sync.sln --verify-no-changes
```

### 6. Commit Changes

```bash
# Stage your changes
git add .

# Commit with descriptive message
git commit -m "Add feature: description of what you added"

# Use conventional commits format
# feat: new feature
# fix: bug fix
# docs: documentation changes
# test: test additions/changes
# refactor: code refactoring
# style: formatting changes
# chore: maintenance tasks
```

### 7. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a pull request on GitHub with:
- Clear description of changes
- Reference to any related issues
- Screenshots if applicable
- Test results

## Code Standards

### PowerShell

#### Naming Conventions
```powershell
# Functions: Verb-Noun format
function Get-UserData { }
function Set-Configuration { }

# Variables: camelCase
$userName = "John"
$configPath = "C:\config"

# Parameters: PascalCase
param([string]$FilePath, [int]$MaxResults)
```

#### Best Practices
```powershell
# Use approved verbs
Get-Verb | Where-Object { $_.Verb -eq "Get" }

# Always include parameter validation
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[string]$FilePath

# Use proper error handling
try {
    # risky operation
} catch {
    Write-Error "Failed to process: $_"
    throw
}

# Include help comments
<#
.SYNOPSIS
    Brief description
.DESCRIPTION
    Detailed description
.PARAMETER FilePath
    Path to the file
.EXAMPLE
    Get-FileContent -FilePath "C:\test.txt"
#>
```

### C# (.NET)

#### Naming Conventions
```csharp
// Classes: PascalCase
public class DocumentProcessor { }

// Methods: PascalCase
public void ProcessDocument() { }

// Properties: PascalCase
public string DocumentPath { get; set; }

// Fields: _camelCase
private readonly HttpClient _httpClient;

// Constants: PascalCase
public const int MaxRetries = 3;
```

#### Best Practices
```csharp
// Use nullable reference types
public string? GetOptionalValue() { }

// Use async/await properly
public async Task<Result> ProcessAsync(CancellationToken ct) { }

// Dispose resources
using var connection = new HttpClient();

// Use guard clauses
if (input == null) throw new ArgumentNullException(nameof(input));

// XML documentation
/// <summary>
/// Processes the document
/// </summary>
/// <param name="path">Path to document</param>
/// <returns>Processing result</returns>
public Result Process(string path) { }
```

## Testing Guidelines

### Test Structure

```powershell
Describe "Component Name" -Tag "Unit" {
    
    BeforeAll {
        # Setup once before all tests
        Import-Module $modulePath -Force
    }
    
    BeforeEach {
        # Setup before each test
        $testData = New-TestDirectory
    }
    
    AfterEach {
        # Cleanup after each test
        Remove-TestDirectory -TestDirectory $testData
    }
    
    Context "Specific Scenario" {
        
        It "Should perform expected action" {
            # Arrange
            $input = "test"
            
            # Act
            $result = My-Function -Input $input
            
            # Assert
            $result | Should -Be "expected"
        }
    }
}
```

### Test Coverage Goals

- **New Code**: 80% minimum
- **Bug Fixes**: Test that reproduces the bug + fix
- **Refactoring**: Maintain existing coverage

### Test Types

1. **Unit Tests** (`-Tag "Unit"`)
   - Fast, isolated tests
   - Mock external dependencies
   - Test one thing at a time

2. **Integration Tests** (`-Tag "Integration"`)
   - Test component interactions
   - Use test databases
   - Verify workflows

3. **E2E Tests** (`-Tag "E2E"`)
   - Test complete scenarios
   - Minimal mocking
   - Slower but comprehensive

## Pull Request Checklist

Before submitting a PR, ensure:

- [ ] Code follows project style guidelines
- [ ] All tests pass locally
- [ ] New tests added for new functionality
- [ ] Code coverage maintained or improved
- [ ] Documentation updated if needed
- [ ] CHANGELOG.md updated (if applicable)
- [ ] Commit messages are clear and descriptive
- [ ] No merge conflicts with main branch
- [ ] PR description explains the changes

## Common Tasks

### Adding a New Module

```powershell
# 1. Create the module file
New-Item -Path "RAG\MyComponent\Modules\MyModule.psm1" -ItemType File

# 2. Create the test file
New-Item -Path "RAG\MyComponent\Tests\Unit\MyModule.Tests.ps1" -ItemType File

# 3. Write your module code

# 4. Write tests

# 5. Export functions
Export-ModuleMember -Function My-Function
```

### Adding a New API Endpoint

```powershell
# 1. Add route in Start-*API.ps1
Add-PodeRoute -Method Get -Path "/api/myendpoint" -ScriptBlock {
    # Implementation
}

# 2. Create function for logic

# 3. Add tests

# 4. Update API documentation
```

### Debugging Tests

```powershell
# Run specific test
Invoke-Pester -Path ".\test.Tests.ps1" -Output Detailed

# Debug a test
$DebugPreference = "Continue"
Invoke-Pester -Path ".\test.Tests.ps1"

# Check test in isolation
It "My test" {
    $result = My-Function
    Write-Host "Result: $result"
    $result | Should -Be "expected"
}
```

## Project Structure

```
RAG/
├── Common/           # Shared utilities (future)
├── FileTracker/      # File monitoring
│   ├── Modules/      # Reusable modules
│   ├── Scripts/      # Executable scripts
│   └── Tests/        # Unit tests
├── Processor/        # Document processing
├── Search/           # Search functionality
├── Vectors/          # Vector operations
│   ├── Modules/      # Core modules
│   ├── Functions/    # API functions
│   ├── Scripts/      # Startup scripts
│   └── Tests/        # Tests
└── Tests/            # Integration tests
    ├── Integration/
    ├── Fixtures/
    └── TestHelpers.psm1
```

## Getting Help

- **Documentation**: Check `docs/` folder
- **Examples**: Look at existing tests
- **Issues**: Search existing GitHub issues
- **Questions**: Open a discussion on GitHub

## Code Review Process

1. **Automated Checks**: CI/CD must pass
2. **Peer Review**: At least one approval required
3. **Testing**: Verify tests cover changes
4. **Documentation**: Check if docs need updates
5. **Merge**: Squash and merge to main

## Release Process

1. Update version numbers
2. Update CHANGELOG.md
3. Tag release in Git
4. Build and test release
5. Create GitHub release
6. Update documentation

## Tips for Success

1. **Start Small**: Make focused, incremental changes
2. **Test First**: Write tests before implementation (TDD)
3. **Ask Questions**: Don't hesitate to ask for clarification
4. **Read Code**: Learn from existing implementation
5. **Be Patient**: Code review takes time
6. **Stay Consistent**: Follow existing patterns
7. **Document**: Update docs as you go
8. **Communicate**: Keep team informed of progress

## License

By contributing, you agree that your contributions will be licensed under the project's license.

## Thank You!

Your contributions help make this project better for everyone. We appreciate your time and effort!

---

For more information, see:
- [Testing Guide](docs/TESTING.md)
- [Architecture Documentation](ARCHITECTURE.md)
- [Project Improvements](PROJECT_IMPROVEMENTS.md)
