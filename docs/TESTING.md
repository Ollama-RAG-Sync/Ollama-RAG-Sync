# Testing Guide

This document describes the testing infrastructure and how to run tests for the Ollama-RAG-Sync project.

## Test Structure

The project uses two testing frameworks:
- **Pester** for PowerShell components (RAG system)
- **xUnit** for .NET components (MCP server)

### Directory Layout

```
RAG/
├── Tests/
│   ├── Integration/
│   │   └── End-to-End.Tests.ps1
│   ├── Fixtures/
│   │   ├── sample-document.txt
│   │   └── sample-document.md
│   └── TestHelpers.psm1
├── FileTracker/
│   └── Tests/
│       └── Unit/
│           └── FileTracker-Shared.Tests.ps1
└── Vectors/
    └── Tests/
        └── Unit/
            └── Vectors-Core.Tests.ps1

MCP/
└── tests/
    └── Ollama-RAG-Sync.Tests/
        ├── HttpClientExtensionsTests.cs
        ├── DataModelsTests.cs
        └── Ollama-RAG-Sync.Tests.csproj
```

## Prerequisites

### PowerShell Tests
```powershell
# Install Pester
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser

# Install PSScriptAnalyzer (for code quality)
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```

### .NET Tests
```powershell
# Ensure .NET 8.0 SDK is installed
dotnet --version  # Should be 8.0 or higher
```

## Running Tests

### Quick Start - Run All Tests
```powershell
# From project root
.\scripts\run-tests.ps1
```

### Run Specific Test Types

#### PowerShell Unit Tests Only
```powershell
.\scripts\run-tests.ps1 -TestType Unit
```

#### PowerShell Integration Tests Only
```powershell
.\scripts\run-tests.ps1 -TestType Integration
```

#### End-to-End Tests Only
```powershell
.\scripts\run-tests.ps1 -TestType E2E
```

#### All PowerShell Tests
```powershell
.\scripts\run-tests.ps1 -TestType PowerShell
```

#### All .NET Tests
```powershell
.\scripts\run-tests.ps1 -TestType DotNet
```

### Test Options

#### Generate Code Coverage
```powershell
.\scripts\run-tests.ps1 -GenerateCoverage
```

#### Detailed Output
```powershell
.\scripts\run-tests.ps1 -Detailed
```

#### Combine Options
```powershell
.\scripts\run-tests.ps1 -TestType Unit -Detailed -GenerateCoverage
```

## Running Tests Directly

### Pester (PowerShell)

#### Run a specific test file
```powershell
Invoke-Pester -Path .\RAG\Vectors\Tests\Unit\Vectors-Core.Tests.ps1
```

#### Run tests with specific tag
```powershell
$config = New-PesterConfiguration
$config.Run.Path = ".\RAG"
$config.Filter.Tag = "Unit"
Invoke-Pester -Configuration $config
```

#### Run with coverage
```powershell
$config = New-PesterConfiguration
$config.Run.Path = ".\RAG"
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = ".\RAG\**\*.psm1"
Invoke-Pester -Configuration $config
```

### xUnit (.NET)

#### Run all .NET tests
```powershell
cd MCP
dotnet test
```

#### Run with detailed output
```powershell
dotnet test --logger "console;verbosity=detailed"
```

#### Run with coverage
```powershell
dotnet test --collect:"XPlat Code Coverage"
```

#### Run specific test class
```powershell
dotnet test --filter "FullyQualifiedName~HttpClientExtensionsTests"
```

## Test Categories

### Unit Tests
- **Tag**: `Unit`
- **Purpose**: Test individual functions in isolation
- **Dependencies**: Mocked or stubbed
- **Speed**: Fast (<1ms per test)
- **Location**: `*/Tests/Unit/`

Example:
```powershell
Describe "Get-FileContent" -Tag "Unit" {
    It "Should read content from a valid text file" {
        # Test implementation
    }
}
```

### Integration Tests
- **Tag**: `Integration`
- **Purpose**: Test component interactions
- **Dependencies**: Real databases (isolated), mock external APIs
- **Speed**: Medium (~100ms per test)
- **Location**: `*/Tests/Integration/`

Example:
```powershell
Describe "FileTracker Integration" -Tag "Integration" {
    It "Should track multiple files through status changes" {
        # Test implementation
    }
}
```

### End-to-End Tests
- **Tag**: `E2E`
- **Purpose**: Test complete workflows
- **Dependencies**: Full system (except external APIs)
- **Speed**: Slow (~1s+ per test)
- **Location**: `RAG/Tests/Integration/`

Example:
```powershell
Describe "End-to-End RAG Workflow" -Tag "E2E" {
    It "Should process documents from start to finish" {
        # Test implementation
    }
}
```

## Writing Tests

### PowerShell Test Template

```powershell
# MyModule.Tests.ps1

BeforeAll {
    # Import module to test
    $modulePath = Join-Path $PSScriptRoot "..\MyModule.psm1"
    Import-Module $modulePath -Force
    
    # Import test helpers
    $testHelpersPath = Join-Path $PSScriptRoot "..\..\Tests\TestHelpers.psm1"
    Import-Module $testHelpersPath -Force
}

Describe "MyModule Function" -Tag "Unit" {
    
    BeforeEach {
        # Setup for each test
        $script:testData = New-TestDirectory
    }
    
    AfterEach {
        # Cleanup after each test
        Remove-TestDirectory -TestDirectory $script:testData
    }
    
    Context "When given valid input" {
        
        It "Should return expected result" {
            # Arrange
            $input = "test value"
            
            # Act
            $result = My-Function -Input $input
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Be "expected value"
        }
    }
    
    Context "When given invalid input" {
        
        It "Should handle errors gracefully" {
            # Arrange
            $input = $null
            
            # Act & Assert
            { My-Function -Input $input } | Should -Throw
        }
    }
}
```

### .NET Test Template

```csharp
using Xunit;
using Moq;

namespace ORSMcp.Tests
{
    public class MyClassTests
    {
        [Fact]
        public void MyMethod_ShouldReturnExpectedValue_WhenGivenValidInput()
        {
            // Arrange
            var input = "test value";
            var expected = "expected value";
            
            // Act
            var result = MyClass.MyMethod(input);
            
            // Assert
            Assert.Equal(expected, result);
        }
        
        [Theory]
        [InlineData("input1", "output1")]
        [InlineData("input2", "output2")]
        public void MyMethod_ShouldHandleMultipleInputs(string input, string expected)
        {
            // Act
            var result = MyClass.MyMethod(input);
            
            // Assert
            Assert.Equal(expected, result);
        }
    }
}
```

## Test Helpers

The `TestHelpers.psm1` module provides utilities for testing:

### Database Helpers
```powershell
# Create temporary test database
$testDb = New-TestDatabase

# Cleanup
Remove-TestDatabase -TestDatabase $testDb
```

### Directory Helpers
```powershell
# Create test directory with sample files
$testDir = New-TestDirectory -FileCount 5 -FileTypes @('.txt', '.md')

# Cleanup
Remove-TestDirectory -TestDirectory $testDir
```

### Configuration Helpers
```powershell
# Create test configuration
$config = New-TestConfig -OllamaUrl "http://localhost:11434"
```

### Mock Data Helpers
```powershell
# Create mock embedding vector
$embedding = New-MockEmbedding -Dimensions 768
```

### Assertion Helpers
```powershell
# Assert equality
Assert-Equal -Expected 5 -Actual $result

# Assert not null or empty
Assert-NotNullOrEmpty -Value $result
```

## Continuous Integration

Tests run automatically on:
- Every push to `main` or `develop` branches
- Every pull request
- Manual workflow dispatch

### CI Pipeline Stages

1. **PowerShell Tests** (Windows, Linux, macOS)
   - Unit tests
   - Code analysis with PSScriptAnalyzer

2. **.NET Tests** (Windows, Linux, macOS)
   - Unit tests
   - Code formatting verification

3. **Integration Tests** (Windows only)
   - End-to-end workflows
   - Database integration

4. **Code Quality**
   - Static analysis
   - Code formatting
   - Security scanning

5. **Build & Package**
   - Create release artifacts

### Viewing CI Results

1. Go to **Actions** tab in GitHub
2. Select the workflow run
3. View job results and logs
4. Download test artifacts if needed

## Code Coverage

### PowerShell Coverage
```powershell
# Generate coverage report
.\scripts\run-tests.ps1 -GenerateCoverage

# View report
coverage\powershell-coverage.xml
```

### .NET Coverage
```powershell
# Generate coverage report
cd MCP
dotnet test --collect:"XPlat Code Coverage"

# Reports in: tests/*/TestResults/*/coverage.cobertura.xml
```

### Coverage Goals

- **Unit Tests**: >80% code coverage
- **Integration Tests**: >60% code coverage
- **Overall**: >70% code coverage

## Troubleshooting

### Pester Module Not Found
```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser
```

### SQLite Errors on Linux/macOS
```bash
# Ubuntu/Debian
sudo apt-get install sqlite3 libsqlite3-dev

# macOS
brew install sqlite
```

### .NET Test Discovery Issues
```powershell
# Clear test cache
dotnet clean
dotnet test --no-build
```

### Test Timeout Issues
Increase timeout in test configuration or mark slow tests with `-Skip`:
```powershell
It "Should handle large files" -Skip {
    # Long-running test
}
```

## Best Practices

1. **Keep tests fast**: Unit tests should run in milliseconds
2. **Test one thing**: Each test should verify one behavior
3. **Use descriptive names**: Test names should describe what's being tested
4. **Clean up resources**: Always cleanup in `AfterEach`/`AfterAll`
5. **Mock external dependencies**: Don't call real APIs in tests
6. **Use test helpers**: Reuse common test utilities
7. **Test error cases**: Don't just test the happy path
8. **Keep tests independent**: Tests should not depend on each other
9. **Use tags**: Categorize tests for selective execution
10. **Document complex tests**: Add comments for non-obvious test logic

## Additional Resources

- [Pester Documentation](https://pester.dev/)
- [xUnit Documentation](https://xunit.net/)
- [Moq Documentation](https://github.com/moq/moq4)
- [.NET Testing Best Practices](https://docs.microsoft.com/en-us/dotnet/core/testing/)
