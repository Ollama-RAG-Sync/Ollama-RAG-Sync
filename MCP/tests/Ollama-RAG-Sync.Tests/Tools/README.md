# SearchTools Tests

This directory contains comprehensive unit tests for the `SearchTools` class.

## Test Coverage

### Constructor Tests (3 tests)
- **Constructor_WithNullSearchService_ShouldThrowArgumentNullException**: Verifies that passing a null `ISearchService` throws an `ArgumentNullException`
- **Constructor_WithNullLogger_ShouldThrowArgumentNullException**: Verifies that passing a null logger throws an `ArgumentNullException`
- **Constructor_WithValidParameters_ShouldCreateInstance**: Verifies successful instantiation with valid dependencies

### LocalDocumentsSearch Tests (8 tests)
- **LocalDocumentsSearch_WithValidRequest_ShouldReturnJsonResults**: Tests successful document search with multiple results and proper JSON serialization
- **LocalDocumentsSearch_WithDefaultParameters_ShouldUseDefaults**: Verifies default parameter values (threshold=0.6, maxResults=2, returnDocument=true)
- **LocalDocumentsSearch_WithCustomParameters_ShouldPassParameters**: Verifies custom parameters are correctly passed to the search service
- **LocalDocumentsSearch_WhenServiceThrowsException_ShouldReturnErrorJson**: Verifies graceful error handling with proper error JSON response
- **LocalDocumentsSearch_WithCancellation_ShouldPassCancellationToken**: Verifies cancellation token is properly propagated
- **LocalDocumentsSearch_ShouldLogInformation**: Verifies informational logging for search operations
- **LocalDocumentsSearch_WhenExceptionOccurs_ShouldLogError**: Verifies error logging when exceptions occur

### LocalChunksSearch Tests (10 tests)
- **LocalChunksSearch_WithoutAggregation_ShouldReturnChunkResults**: Tests non-aggregated chunk search with proper JSON serialization
- **LocalChunksSearch_WithAggregation_ShouldReturnAggregatedResults**: Tests aggregated chunk search grouped by document
- **LocalChunksSearch_WithDefaultParameters_ShouldUseDefaults**: Verifies default parameter values (threshold=0.6, maxResults=2, aggregateByDocument=false)
- **LocalChunksSearch_WithCustomParameters_ShouldPassParameters**: Verifies custom parameters are correctly passed to the search service
- **LocalChunksSearch_WhenServiceThrowsException_ShouldReturnErrorJson**: Verifies error handling for non-aggregated search
- **LocalChunksSearch_WithAggregation_WhenServiceThrowsException_ShouldReturnErrorJson**: Verifies error handling for aggregated search
- **LocalChunksSearch_WithCancellation_ShouldPassCancellationToken**: Verifies cancellation token propagation
- **LocalChunksSearch_ShouldLogInformation**: Verifies informational logging for chunk search operations
- **LocalChunksSearch_WhenExceptionOccurs_ShouldLogError**: Verifies error logging when exceptions occur
- **LocalChunksSearch_WithAggregationTrue_ShouldCallAggregatedService**: Verifies correct service method is called for aggregated search
- **LocalChunksSearch_WithAggregationFalse_ShouldCallNonAggregatedService**: Verifies correct service method is called for non-aggregated search

## Test Patterns

All tests follow these patterns:
1. **Arrange**: Set up mocks, expected responses, and test data
2. **Act**: Call the method under test
3. **Assert**: Verify the expected behavior

## Mocking Strategy

- Uses `Moq` framework for creating mock objects
- Mocks `ISearchService` to isolate SearchTools from search service implementation
- Mocks `ILogger<SearchTools>` to verify logging behavior
- Uses `xUnit` as the test framework

## Running the Tests

To run only the SearchTools tests:
```bash
dotnet test --filter "FullyQualifiedName~SearchToolsTests"
```

To run all tests:
```bash
dotnet test
```

## Test Results

All 21 tests pass successfully ?
