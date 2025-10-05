# Ollama-RAG-Sync Tests

This directory contains unit tests for the Ollama-RAG-Sync MCP server.

## Test Coverage

The test suite covers the following components:

### 1. DataModelsTests.cs
- **RequestData**: Tests serialization and JSON property naming
- **ChunkRequestData**: Tests serialization and JSON property naming
- **DocumentResponseData**: Tests deserialization from API responses
- **ChunkResponseData**: Tests deserialization for chunk search results
- **ChunkAggregatedResponseData**: Tests deserialization for aggregated chunk results

### 2. HttpClientExtTests.cs
- **ReadJsonDocumentsAsync**: Tests document search HTTP requests and responses
- **ReadJsonChunksAsync**: Tests chunk search HTTP requests (non-aggregated)
- **ReadJsonChunksAggregatedAsync**: Tests aggregated chunk search HTTP requests
- Error handling and validation tests

### 3. MCPsTests.cs
- **LocalDocumentsSearch**: Tests the MCP tool for document searches
- **LocalChunksSearch**: Tests the MCP tool for chunk searches (both aggregated and non-aggregated)
- Parameter handling and serialization tests

## Running the Tests

### Using Visual Studio
1. Open the Test Explorer (Test > Test Explorer)
2. Click "Run All" to execute all tests

### Using Command Line
```bash
cd Ollama-RAG-Sync.Tests
dotnet test
```

### With Code Coverage
```bash
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=opencover
```

## Test Frameworks and Libraries

- **xUnit**: Testing framework
- **Moq**: Mocking library for HTTP client testing
- **coverlet**: Code coverage tool

## Environment Variables

Some tests require the `OLLAMA_RAG_VECTORS_API_PORT` environment variable to be set. The tests set this to a default value of "5000" for testing purposes.

## Adding New Tests

When adding new functionality to the main project:

1. Add corresponding test methods in the appropriate test class
2. Follow the Arrange-Act-Assert pattern
3. Use descriptive test method names following the pattern: `MethodName_Scenario_ExpectedBehavior`
4. Mock external dependencies (HTTP calls, file system, etc.)

## Test Conventions

- Each test is independent and can run in any order
- Tests use mocked HTTP responses to avoid external dependencies
- Tests focus on behavior verification rather than implementation details
