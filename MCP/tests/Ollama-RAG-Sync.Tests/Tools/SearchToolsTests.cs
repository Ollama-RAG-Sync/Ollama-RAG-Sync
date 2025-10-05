using Microsoft.Extensions.Logging;
using Moq;
using ORSMcp.Models;
using ORSMcp.Services;
using ORSMcp.Tools;
using System.Text.Json;

namespace ORSMcp.Tests.Tools
{
    public class SearchToolsTests
    {
        private readonly Mock<ISearchService> _mockSearchService;
        private readonly Mock<ILogger<SearchTools>> _mockLogger;
        private readonly SearchTools _searchTools;

        public SearchToolsTests()
        {
            _mockSearchService = new Mock<ISearchService>();
            _mockLogger = new Mock<ILogger<SearchTools>>();
            _searchTools = new SearchTools(_mockSearchService.Object, _mockLogger.Object);
        }

        #region Constructor Tests

        [Fact]
        public void Constructor_WithNullSearchService_ShouldThrowArgumentNullException()
        {
            // Act & Assert
            var exception = Assert.Throws<ArgumentNullException>(() =>
                new SearchTools(null!, _mockLogger.Object));
            Assert.Equal("searchService", exception.ParamName);
        }

        [Fact]
        public void Constructor_WithNullLogger_ShouldThrowArgumentNullException()
        {
            // Act & Assert
            var exception = Assert.Throws<ArgumentNullException>(() =>
                new SearchTools(_mockSearchService.Object, null!));
            Assert.Equal("logger", exception.ParamName);
        }

        [Fact]
        public void Constructor_WithValidParameters_ShouldCreateInstance()
        {
            // Act
            var searchTools = new SearchTools(_mockSearchService.Object, _mockLogger.Object);

            // Assert
            Assert.NotNull(searchTools);
        }

        #endregion

        #region LocalDocumentsSearch Tests

        [Fact]
        public async Task LocalDocumentsSearch_WithValidRequest_ShouldReturnJsonResults()
        {
            // Arrange
            var expectedResponse = new DocumentSearchResponse
            {
                Success = true,
                Results = new[]
                {
                    new DocumentSearchResult
                    {
                        Id = "doc1",
                        Source = "test.txt",
                        Document = "Test document content",
                        Similarity = 0.95m
                    },
                    new DocumentSearchResult
                    {
                        Id = "doc2",
                        Source = "test2.txt",
                        Document = "Another document",
                        Similarity = 0.85m
                    }
                }
            };

            _mockSearchService
                .Setup(s => s.SearchDocumentsAsync(It.IsAny<DocumentSearchRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(expectedResponse);

            // Act
            var result = await _searchTools.LocalDocumentsSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                threshold: 0.7m,
                maxResults: 5,
                returnDocument: true);

            // Assert
            Assert.NotNull(result);
            var deserializedResult = JsonSerializer.Deserialize<DocumentSearchResponse>(result);
            Assert.NotNull(deserializedResult);
            Assert.True(deserializedResult.Success);
            Assert.Equal(2, deserializedResult.Results.Length);
            Assert.Equal("doc1", deserializedResult.Results[0].Id);
            Assert.Equal(0.95m, deserializedResult.Results[0].Similarity);
        }

        [Fact]
        public async Task LocalDocumentsSearch_WithDefaultParameters_ShouldUseDefaults()
        {
            // Arrange
            DocumentSearchRequest? capturedRequest = null;
            _mockSearchService
                .Setup(s => s.SearchDocumentsAsync(It.IsAny<DocumentSearchRequest>(), It.IsAny<CancellationToken>()))
                .Callback<DocumentSearchRequest, CancellationToken>((req, ct) => capturedRequest = req)
                .ReturnsAsync(new DocumentSearchResponse { Success = true, Results = Array.Empty<DocumentSearchResult>() });

            // Act
            await _searchTools.LocalDocumentsSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None);

            // Assert
            Assert.NotNull(capturedRequest);
            Assert.Equal("test query", capturedRequest.Query);
            Assert.Equal("test-collection", capturedRequest.CollectionName);
            Assert.Equal(0.6m, capturedRequest.Threshold); // Default
            Assert.Equal(2, capturedRequest.MaxResults); // Default
            Assert.True(capturedRequest.ReturnContent); // Default
        }

        [Fact]
        public async Task LocalDocumentsSearch_WithCustomParameters_ShouldPassParameters()
        {
            // Arrange
            DocumentSearchRequest? capturedRequest = null;
            _mockSearchService
                .Setup(s => s.SearchDocumentsAsync(It.IsAny<DocumentSearchRequest>(), It.IsAny<CancellationToken>()))
                .Callback<DocumentSearchRequest, CancellationToken>((req, ct) => capturedRequest = req)
                .ReturnsAsync(new DocumentSearchResponse { Success = true, Results = Array.Empty<DocumentSearchResult>() });

            // Act
            await _searchTools.LocalDocumentsSearch(
                prompt: "custom query",
                collectionName: "custom-collection",
                cancellationToken: CancellationToken.None,
                threshold: 0.8m,
                maxResults: 10,
                returnDocument: false);

            // Assert
            Assert.NotNull(capturedRequest);
            Assert.Equal("custom query", capturedRequest.Query);
            Assert.Equal("custom-collection", capturedRequest.CollectionName);
            Assert.Equal(0.8m, capturedRequest.Threshold);
            Assert.Equal(10, capturedRequest.MaxResults);
            Assert.False(capturedRequest.ReturnContent);
        }

        [Fact]
        public async Task LocalDocumentsSearch_WhenServiceThrowsException_ShouldReturnErrorJson()
        {
            // Arrange
            var expectedException = new InvalidOperationException("Search service error");
            _mockSearchService
                .Setup(s => s.SearchDocumentsAsync(It.IsAny<DocumentSearchRequest>(), It.IsAny<CancellationToken>()))
                .ThrowsAsync(expectedException);

            // Act
            var result = await _searchTools.LocalDocumentsSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None);

            // Assert
            Assert.NotNull(result);
            var errorResponse = JsonSerializer.Deserialize<Dictionary<string, object>>(result);
            Assert.NotNull(errorResponse);
            Assert.False(errorResponse["success"].ToString() == "True");
            Assert.Contains("Search service error", errorResponse["error"].ToString());
            Assert.Equal("InvalidOperationException", errorResponse["errorType"].ToString());
        }

        [Fact]
        public async Task LocalDocumentsSearch_WithCancellation_ShouldPassCancellationToken()
        {
            // Arrange
            var cts = new CancellationTokenSource();
            CancellationToken capturedToken = default;
            
            _mockSearchService
                .Setup(s => s.SearchDocumentsAsync(It.IsAny<DocumentSearchRequest>(), It.IsAny<CancellationToken>()))
                .Callback<DocumentSearchRequest, CancellationToken>((req, ct) => capturedToken = ct)
                .ReturnsAsync(new DocumentSearchResponse { Success = true, Results = Array.Empty<DocumentSearchResult>() });

            // Act
            await _searchTools.LocalDocumentsSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: cts.Token);

            // Assert
            Assert.Equal(cts.Token, capturedToken);
        }

        [Fact]
        public async Task LocalDocumentsSearch_ShouldLogInformation()
        {
            // Arrange
            _mockSearchService
                .Setup(s => s.SearchDocumentsAsync(It.IsAny<DocumentSearchRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(new DocumentSearchResponse { Success = true, Results = Array.Empty<DocumentSearchResult>() });

            // Act
            await _searchTools.LocalDocumentsSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None);

            // Assert
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Information,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("LocalDocumentsSearch called")),
                    It.IsAny<Exception>(),
                    It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
                Times.Once);
        }

        [Fact]
        public async Task LocalDocumentsSearch_WhenExceptionOccurs_ShouldLogError()
        {
            // Arrange
            var expectedException = new InvalidOperationException("Test error");
            _mockSearchService
                .Setup(s => s.SearchDocumentsAsync(It.IsAny<DocumentSearchRequest>(), It.IsAny<CancellationToken>()))
                .ThrowsAsync(expectedException);

            // Act
            await _searchTools.LocalDocumentsSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None);

            // Assert
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Error,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("Error in LocalDocumentsSearch")),
                    expectedException,
                    It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
                Times.Once);
        }

        #endregion

        #region LocalChunksSearch Tests

        [Fact]
        public async Task LocalChunksSearch_WithoutAggregation_ShouldReturnChunkResults()
        {
            // Arrange
            var expectedResponse = new ChunkSearchResponse
            {
                Success = true,
                Results = new[]
                {
                    new ChunkSearchResult
                    {
                        Id = "chunk1",
                        Source = "test.txt",
                        Chunk = "Test chunk content",
                        Similarity = 0.92m,
                        Metadata = new ChunkMetadata
                        {
                            LineRange = "1-10"
                        }
                    }
                }
            };

            _mockSearchService
                .Setup(s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(expectedResponse);

            // Act
            var result = await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                threshold: 0.7m,
                maxResults: 5,
                aggregateByDocument: false);

            // Assert
            Assert.NotNull(result);
            var deserializedResult = JsonSerializer.Deserialize<ChunkSearchResponse>(result);
            Assert.NotNull(deserializedResult);
            Assert.True(deserializedResult.Success);
            Assert.Single(deserializedResult.Results);
            Assert.Equal("chunk1", deserializedResult.Results[0].Id);
            Assert.Equal(0.92m, deserializedResult.Results[0].Similarity);
        }

        [Fact]
        public async Task LocalChunksSearch_WithAggregation_ShouldReturnAggregatedResults()
        {
            // Arrange
            var expectedResponse = new ChunkAggregatedSearchResponse
            {
                Success = true,
                Results = new[]
                {
                    new AggregatedChunkResult
                    {
                        Source = "test.txt",
                        Chunks = new[]
                        {
                            new ChunkSearchResult
                            {
                                Id = "chunk1",
                                Source = "test.txt",
                                Chunk = "First chunk",
                                Similarity = 0.95m,
                                Metadata = new ChunkMetadata { LineRange = "1-10" }
                            },
                            new ChunkSearchResult
                            {
                                Id = "chunk2",
                                Source = "test.txt",
                                Chunk = "Second chunk",
                                Similarity = 0.88m,
                                Metadata = new ChunkMetadata { LineRange = "11-20" }
                            }
                        }
                    }
                }
            };

            _mockSearchService
                .Setup(s => s.SearchChunksAggregatedAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(expectedResponse);

            // Act
            var result = await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                threshold: 0.7m,
                maxResults: 5,
                aggregateByDocument: true);

            // Assert
            Assert.NotNull(result);
            var deserializedResult = JsonSerializer.Deserialize<ChunkAggregatedSearchResponse>(result);
            Assert.NotNull(deserializedResult);
            Assert.True(deserializedResult.Success);
            Assert.Single(deserializedResult.Results);
            Assert.Equal("test.txt", deserializedResult.Results[0].Source);
            Assert.Equal(2, deserializedResult.Results[0].Chunks.Length);
        }

        [Fact]
        public async Task LocalChunksSearch_WithDefaultParameters_ShouldUseDefaults()
        {
            // Arrange
            ChunkSearchRequest? capturedRequest = null;
            _mockSearchService
                .Setup(s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .Callback<ChunkSearchRequest, CancellationToken>((req, ct) => capturedRequest = req)
                .ReturnsAsync(new ChunkSearchResponse { Success = true, Results = Array.Empty<ChunkSearchResult>() });

            // Act
            await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None);

            // Assert
            Assert.NotNull(capturedRequest);
            Assert.Equal("test query", capturedRequest.Query);
            Assert.Equal("test-collection", capturedRequest.CollectionName);
            Assert.Equal(0.6m, capturedRequest.Threshold); // Default
            Assert.Equal(2, capturedRequest.MaxResults); // Default
            Assert.False(capturedRequest.AggregateByDocument); // Default
        }

        [Fact]
        public async Task LocalChunksSearch_WithCustomParameters_ShouldPassParameters()
        {
            // Arrange
            ChunkSearchRequest? capturedRequest = null;
            _mockSearchService
                .Setup(s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .Callback<ChunkSearchRequest, CancellationToken>((req, ct) => capturedRequest = req)
                .ReturnsAsync(new ChunkSearchResponse { Success = true, Results = Array.Empty<ChunkSearchResult>() });

            // Act
            await _searchTools.LocalChunksSearch(
                prompt: "custom query",
                collectionName: "custom-collection",
                cancellationToken: CancellationToken.None,
                threshold: 0.85m,
                maxResults: 15,
                aggregateByDocument: false);

            // Assert
            Assert.NotNull(capturedRequest);
            Assert.Equal("custom query", capturedRequest.Query);
            Assert.Equal("custom-collection", capturedRequest.CollectionName);
            Assert.Equal(0.85m, capturedRequest.Threshold);
            Assert.Equal(15, capturedRequest.MaxResults);
            Assert.False(capturedRequest.AggregateByDocument);
        }

        [Fact]
        public async Task LocalChunksSearch_WhenServiceThrowsException_ShouldReturnErrorJson()
        {
            // Arrange
            var expectedException = new InvalidOperationException("Chunk search error");
            _mockSearchService
                .Setup(s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .ThrowsAsync(expectedException);

            // Act
            var result = await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                aggregateByDocument: false);

            // Assert
            Assert.NotNull(result);
            var errorResponse = JsonSerializer.Deserialize<Dictionary<string, object>>(result);
            Assert.NotNull(errorResponse);
            Assert.False(errorResponse["success"].ToString() == "True");
            Assert.Contains("Chunk search error", errorResponse["error"].ToString());
            Assert.Equal("InvalidOperationException", errorResponse["errorType"].ToString());
        }

        [Fact]
        public async Task LocalChunksSearch_WithAggregation_WhenServiceThrowsException_ShouldReturnErrorJson()
        {
            // Arrange
            var expectedException = new InvalidOperationException("Aggregated search error");
            _mockSearchService
                .Setup(s => s.SearchChunksAggregatedAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .ThrowsAsync(expectedException);

            // Act
            var result = await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                aggregateByDocument: true);

            // Assert
            Assert.NotNull(result);
            var errorResponse = JsonSerializer.Deserialize<Dictionary<string, object>>(result);
            Assert.NotNull(errorResponse);
            Assert.False(errorResponse["success"].ToString() == "True");
            Assert.Contains("Aggregated search error", errorResponse["error"].ToString());
        }

        [Fact]
        public async Task LocalChunksSearch_WithCancellation_ShouldPassCancellationToken()
        {
            // Arrange
            var cts = new CancellationTokenSource();
            CancellationToken capturedToken = default;
            
            _mockSearchService
                .Setup(s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .Callback<ChunkSearchRequest, CancellationToken>((req, ct) => capturedToken = ct)
                .ReturnsAsync(new ChunkSearchResponse { Success = true, Results = Array.Empty<ChunkSearchResult>() });

            // Act
            await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: cts.Token,
                aggregateByDocument: false);

            // Assert
            Assert.Equal(cts.Token, capturedToken);
        }

        [Fact]
        public async Task LocalChunksSearch_ShouldLogInformation()
        {
            // Arrange
            _mockSearchService
                .Setup(s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(new ChunkSearchResponse { Success = true, Results = Array.Empty<ChunkSearchResult>() });

            // Act
            await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                aggregateByDocument: false);

            // Assert
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Information,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("LocalChunksSearch called")),
                    It.IsAny<Exception>(),
                    It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
                Times.Once);
        }

        [Fact]
        public async Task LocalChunksSearch_WhenExceptionOccurs_ShouldLogError()
        {
            // Arrange
            var expectedException = new InvalidOperationException("Test error");
            _mockSearchService
                .Setup(s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .ThrowsAsync(expectedException);

            // Act
            await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                aggregateByDocument: false);

            // Assert
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Error,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("Error in LocalChunksSearch")),
                    expectedException,
                    It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
                Times.Once);
        }

        [Fact]
        public async Task LocalChunksSearch_WithAggregationTrue_ShouldCallAggregatedService()
        {
            // Arrange
            _mockSearchService
                .Setup(s => s.SearchChunksAggregatedAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(new ChunkAggregatedSearchResponse { Success = true, Results = Array.Empty<AggregatedChunkResult>() });

            // Act
            await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                aggregateByDocument: true);

            // Assert
            _mockSearchService.Verify(
                s => s.SearchChunksAggregatedAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()),
                Times.Once);
            _mockSearchService.Verify(
                s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()),
                Times.Never);
        }

        [Fact]
        public async Task LocalChunksSearch_WithAggregationFalse_ShouldCallNonAggregatedService()
        {
            // Arrange
            _mockSearchService
                .Setup(s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(new ChunkSearchResponse { Success = true, Results = Array.Empty<ChunkSearchResult>() });

            // Act
            await _searchTools.LocalChunksSearch(
                prompt: "test query",
                collectionName: "test-collection",
                cancellationToken: CancellationToken.None,
                aggregateByDocument: false);

            // Assert
            _mockSearchService.Verify(
                s => s.SearchChunksAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()),
                Times.Once);
            _mockSearchService.Verify(
                s => s.SearchChunksAggregatedAsync(It.IsAny<ChunkSearchRequest>(), It.IsAny<CancellationToken>()),
                Times.Never);
        }

        #endregion
    }
}
