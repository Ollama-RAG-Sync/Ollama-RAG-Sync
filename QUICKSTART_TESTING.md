# Quick Start Guide - Testing

## 🚀 Get Started in 5 Minutes

### Step 1: Install Prerequisites (2 min)

```powershell
# Install Pester for PowerShell testing
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser

# Verify .NET SDK (should be 8.0+)
dotnet --version
```

### Step 2: Run All Tests (1 min)

```powershell
# Navigate to project root
cd c:\Users\marci\RAg\Ollama-RAG-Sync

# Run all tests
.\scripts\run-tests.ps1
```

### Step 3: Run Specific Tests (1 min)

```powershell
# Run only unit tests (fast)
.\scripts\run-tests.ps1 -TestType Unit

# Run only .NET tests
.\scripts\run-tests.ps1 -TestType DotNet

# Run with detailed output
.\scripts\run-tests.ps1 -Detailed
```

### Step 4: View Results (1 min)

Look for the test summary at the end:
```
========================================
  Test Summary
========================================

PowerShell Tests:
  Total:   45
  Passed:  45
  Failed:  0
  Skipped: 0

.NET Tests:
  Status: PASSED

All tests passed! ✓
```

## 📝 Quick Test Writing Guide

### PowerShell Test Template

Create a file: `MyModule.Tests.ps1`

```powershell
BeforeAll {
    Import-Module ".\MyModule.psm1" -Force
}

Describe "MyFunction" -Tag "Unit" {
    It "Should return expected value" {
        # Arrange
        $input = "test"
        
        # Act
        $result = MyFunction -Input $input
        
        # Assert
        $result | Should -Be "expected"
    }
}
```

Run it:
```powershell
Invoke-Pester -Path ".\MyModule.Tests.ps1"
```

### C# Test Template

Create a file: `MyClassTests.cs`

```csharp
using Xunit;

public class MyClassTests
{
    [Fact]
    public void MyMethod_ShouldReturnExpected()
    {
        // Arrange
        var input = "test";
        
        // Act
        var result = MyClass.MyMethod(input);
        
        // Assert
        Assert.Equal("expected", result);
    }
}
```

Run it:
```powershell
dotnet test
```

## 🎯 Common Commands

```powershell
# Run all tests
.\scripts\run-tests.ps1

# Run unit tests only (fastest)
.\scripts\run-tests.ps1 -TestType Unit

# Run integration tests
.\scripts\run-tests.ps1 -TestType Integration

# Run end-to-end tests
.\scripts\run-tests.ps1 -TestType E2E

# Generate code coverage
.\scripts\run-tests.ps1 -GenerateCoverage

# Run with verbose output
.\scripts\run-tests.ps1 -Detailed

# Run specific test file
Invoke-Pester -Path ".\RAG\Vectors\Tests\Unit\Vectors-Core.Tests.ps1"
```

## 🔍 Understanding Test Results

### Passed Test ✅
```
[+] Should read content from a valid text file 45ms (34ms|11ms)
```
- Test passed
- Took 45ms total
- 34ms for test execution, 11ms for setup/teardown

### Failed Test ❌
```
[-] Should handle invalid input 89ms (67ms|22ms)
  Expected strings to be the same, but they were different.
  Expected: 'expected'
  Actual:   'actual'
```
- Test failed
- Shows what was expected vs actual
- Includes timing information

### Skipped Test ⚠️
```
[!] Should connect to Ollama 0ms (0ms|0ms)
```
- Test was skipped (marked with `-Skip`)
- Usually for tests requiring external dependencies

## 📚 Key Test Files

| File | Purpose | Type |
|------|---------|------|
| `TestHelpers.psm1` | Shared test utilities | Helper |
| `Vectors-Core.Tests.ps1` | Vector operations tests | Unit |
| `FileTracker-Shared.Tests.ps1` | File tracking tests | Unit |
| `End-to-End.Tests.ps1` | Complete workflow tests | Integration |
| `HttpClientExtensionsTests.cs` | HTTP client tests | Unit (.NET) |
| `DataModelsTests.cs` | Data model tests | Unit (.NET) |

## 🛠️ Test Helpers Available

```powershell
# Create test database
$testDb = New-TestDatabase
Remove-TestDatabase -TestDatabase $testDb

# Create test directory with files
$testDir = New-TestDirectory -FileCount 5 -FileTypes @('.txt', '.md')
Remove-TestDirectory -TestDirectory $testDir

# Create test configuration
$config = New-TestConfig

# Create mock embedding
$embedding = New-MockEmbedding -Dimensions 768

# Wait for endpoint
Wait-ForEndpoint -Uri "http://localhost:10001/api/health" -TimeoutSeconds 30

# Assertions
Assert-Equal -Expected 5 -Actual $result
Assert-NotNullOrEmpty -Value $result
```

## 🐛 Troubleshooting

### "Module not found"
```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser
```

### "dotnet not found"
Download and install .NET 8.0 SDK from: https://dotnet.microsoft.com/download

### Tests fail with database errors
```powershell
# Clean up any leftover test databases
Remove-Item "$env:TEMP\test_*.db" -Force -ErrorAction SilentlyContinue
```

### Tests are slow
```powershell
# Run only unit tests (they're fast)
.\scripts\run-tests.ps1 -TestType Unit
```

## 📖 More Information

- **Full Testing Guide**: `docs\TESTING.md`
- **Architecture Docs**: `ARCHITECTURE.md`
- **Contributing Guide**: `docs\CONTRIBUTING.md`
- **Project Summary**: `PROJECT_IMPROVEMENTS.md`

## ✨ Next Steps

1. ✅ Run tests to verify everything works
2. ✅ Write a test for a new feature
3. ✅ Check code coverage with `-GenerateCoverage`
4. ✅ Review existing tests to learn patterns
5. ✅ Contribute your improvements!

---

**Need Help?** Check `docs\TESTING.md` for comprehensive documentation.
