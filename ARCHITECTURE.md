# Ollama-RAG-Sync Architecture

## Improved Project Structure

This document describes the improved architecture and testing strategy for the Ollama-RAG-Sync project.

## Directory Structure

```
Ollama-RAG-Sync/
├── .github/
│   └── workflows/
│       └── ci.yml                  # CI/CD pipeline configuration
├── docs/                           # Documentation
│   ├── API.md                      # API documentation
│   ├── CONTRIBUTING.md             # Contributing guidelines
│   └── DEPLOYMENT.md               # Deployment guide
├── MCP/                            # Model Context Protocol Server (.NET)
│   ├── src/
│   │   ├── Program.cs
│   │   ├── Models/                 # Data models
│   │   ├── Services/               # Business logic services
│   │   └── Extensions/             # HTTP client extensions
│   ├── tests/
│   │   └── Ollama-RAG-Sync.Tests/  # xUnit tests
│   ├── Ollama-RAG-Sync.csproj
│   └── Ollama-RAG-Sync.sln
├── RAG/                            # RAG System Components (PowerShell)
│   ├── Common/                     # Shared utilities and helpers
│   │   ├── Config.psm1             # Configuration management
│   │   ├── Logger.psm1             # Centralized logging
│   │   └── Validation.psm1         # Input validation helpers
│   ├── FileTracker/
│   │   ├── Modules/
│   │   │   ├── Database-Shared.psm1
│   │   │   └── FileTracker-Shared.psm1
│   │   ├── Scripts/
│   │   │   ├── Add-Folder.ps1
│   │   │   ├── Get-CollectionFiles.ps1
│   │   │   ├── Get-FileTrackerStatus.ps1
│   │   │   ├── Initialize-Database.ps1
│   │   │   ├── Install-FileTracker.ps1
│   │   │   ├── Refresh-Collection.ps1
│   │   │   ├── Start-FileTrackerAPI.ps1
│   │   │   ├── Update-CollectionStatus.ps1
│   │   │   └── Update-FileStatus.ps1
│   │   └── Tests/
│   │       ├── Unit/
│   │       │   ├── Database-Shared.Tests.ps1
│   │       │   └── FileTracker-Shared.Tests.ps1
│   │       └── Integration/
│   │           └── FileTracker-Integration.Tests.ps1
│   ├── Processor/
│   │   ├── Modules/
│   │   │   └── Processor-Core.psm1
│   │   ├── Scripts/
│   │   │   ├── Process-Collection.ps1
│   │   │   └── Process-Document.ps1
│   │   ├── Conversion/
│   │   │   └── Convert-PDFToMarkdown.ps1
│   │   └── Tests/
│   │       └── Unit/
│   │           └── Processor-Core.Tests.ps1
│   ├── Search/
│   │   ├── Scripts/
│   │   │   ├── Get-BestChunks.ps1
│   │   │   └── Get-BestDocuments.ps1
│   │   └── Tests/
│   │       └── Unit/
│   │           └── Search.Tests.ps1
│   ├── Vectors/
│   │   ├── Modules/
│   │   │   ├── Vectors-Core.psm1
│   │   │   ├── Vectors-Database.psm1
│   │   │   └── Vectors-Embeddings.psm1
│   │   ├── Functions/
│   │   │   ├── Add-DocumentToVectors.ps1
│   │   │   ├── Get-ChunksByQuery.ps1
│   │   │   ├── Get-DocumentsByQuery.ps1
│   │   │   ├── Initialize-VectorDatabase.ps1
│   │   │   └── Remove-DocumentFromVectors.ps1
│   │   ├── Scripts/
│   │   │   └── Start-VectorsAPI.ps1
│   │   ├── Tests/
│   │   │   ├── Unit/
│   │   │   │   ├── Vectors-Core.Tests.ps1
│   │   │   │   ├── Vectors-Database.Tests.ps1
│   │   │   │   └── Vectors-Embeddings.Tests.ps1
│   │   │   └── Integration/
│   │   │       └── Vectors-Integration.Tests.ps1
│   │   └── server.psd1
│   ├── Tests/
│   │   ├── Integration/
│   │   │   └── End-to-End.Tests.ps1  # Full workflow tests
│   │   ├── Fixtures/                  # Test data and fixtures
│   │   │   ├── sample-documents/
│   │   │   └── test-config.json
│   │   └── TestHelpers.psm1           # Shared test utilities
│   ├── Setup-RAG.ps1
│   └── Start-RAG.ps1
├── scripts/                        # Build and deployment scripts
│   ├── build.ps1
│   ├── run-tests.ps1
│   └── deploy.ps1
├── .gitignore
├── ARCHITECTURE.md                 # This file
├── LICENSE
└── README.md
```

## Key Improvements

### 1. **Separation of Concerns**
- **Modules/** folders contain reusable PowerShell modules
- **Scripts/** folders contain executable scripts
- **Functions/** folders contain individual function files
- **Tests/** folders organized by test type (Unit/Integration)

### 2. **Common Utilities**
- Centralized configuration management
- Shared logging functionality
- Common validation helpers
- Reduces code duplication across components

### 3. **Comprehensive Testing**
- **Unit Tests**: Test individual functions and modules in isolation
- **Integration Tests**: Test component interactions
- **End-to-End Tests**: Test complete workflows
- Test fixtures for consistent test data

### 4. **MCP Server Organization**
- Separate Models, Services, and Extensions
- Dedicated test project with proper references
- Better maintainability and testability

### 5. **CI/CD Integration**
- Automated testing on every commit
- Multi-platform test execution
- Code quality checks

## Testing Strategy

### PowerShell Tests (Pester Framework)

#### Unit Tests
- Mock external dependencies (Ollama API, ChromaDB, SQLite)
- Test individual functions in isolation
- Fast execution, no external dependencies
- Located in component-specific Tests/Unit folders

#### Integration Tests
- Test interactions between components
- Use test databases and mock servers
- Verify API endpoints
- Located in component-specific Tests/Integration folders

#### End-to-End Tests
- Test complete workflows (add folder → process → search)
- Use temporary test environment
- Validate system behavior from user perspective
- Located in RAG/Tests/Integration

### .NET Tests (xUnit Framework)

#### MCP Server Tests
- Unit tests for models and services
- Integration tests for HTTP clients
- Mock HTTP responses
- Test MCP protocol compliance

## Testing Commands

### Run All Tests
```powershell
# PowerShell tests
.\scripts\run-tests.ps1

# .NET tests
dotnet test .\MCP\Ollama-RAG-Sync.sln
```

### Run Specific Test Categories
```powershell
# Unit tests only
Invoke-Pester -Path .\RAG\ -Tag "Unit"

# Integration tests only
Invoke-Pester -Path .\RAG\ -Tag "Integration"

# Specific component tests
Invoke-Pester -Path .\RAG\FileTracker\Tests\
```

## Configuration Management

### Environment Variables
All configuration uses a consistent pattern:
- `OLLAMA_RAG_*` prefix for all environment variables
- Fallback to sensible defaults
- Validated at startup

### Test Configuration
- Separate test configuration files
- Isolated test databases
- No impact on production/development data

## Best Practices

### 1. **Module Development**
- Each module exports only necessary functions
- Use proper parameter validation
- Include comprehensive help comments
- Follow PowerShell naming conventions

### 2. **Testing**
- Write tests before implementing features (TDD)
- Aim for >80% code coverage
- Use descriptive test names
- Clean up test resources in AfterEach/AfterAll blocks

### 3. **Error Handling**
- Use try-catch blocks appropriately
- Log errors with context
- Return meaningful error messages
- Use proper exit codes

### 4. **Documentation**
- Keep README.md updated
- Document all public functions
- Include usage examples
- Maintain API documentation

## Migration Path

To migrate existing code to the new structure:

1. ✅ Create new directory structure
2. ✅ Move files to appropriate locations
3. ✅ Update import paths
4. ✅ Add test infrastructure
5. ✅ Write tests for existing functionality
6. ✅ Refactor for better testability
7. ✅ Update documentation
8. ✅ Set up CI/CD

## Dependencies

### PowerShell
- PowerShell 7.0+
- Pester 5.0+ (testing framework)
- Pode (REST API framework)

### Python
- Python 3.8+
- chromadb
- requests
- numpy

### .NET
- .NET 8.0 SDK
- xUnit (testing framework)
- Moq (mocking framework)
- ModelContextProtocol package

## Performance Considerations

- Use transactions for batch database operations
- Implement caching where appropriate
- Optimize chunking strategy for large documents
- Consider parallel processing for multiple documents
- Monitor memory usage for large vector operations

## Security Considerations

- Validate all file paths
- Sanitize user inputs
- Use parameterized SQL queries
- Implement rate limiting on APIs
- Consider authentication for production use
