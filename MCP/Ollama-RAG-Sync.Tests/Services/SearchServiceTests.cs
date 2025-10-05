using Microsoft.Extensions.Logging;
using Moq;
using Moq.Protected;
using ORSMcp.Exceptions;
using ORSMcp.Models;
using ORSMcp.Services;
using System.Net;
using System.Text.Json;

namespace ORSMcp.Tests.Services
{
    public class SearchServiceTests
    {
        private readonly Mock<ILogger<SearchService>> _mockLogger;
        private const string TestVectorPort = "10001";

        public SearchServiceTests()
        {
            _mockLogger = new Mock<ILogger<SearchService>>();
            Environment.SetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", TestVectorPort, EnvironmentVariableTarget.User);
        }

        private HttpClient CreateMockHttpClient(HttpStatusCode statusCode, string responseContent)
        {
            var mockHandler = new Mock<HttpMessageHandler>();
            mockHandler
                .Protected()
                .Setup<Task<HttpResponseMessage>>(
                    "SendAsync",
                    ItExpr.IsAny<HttpRequestMessage>(),
                    ItExpr.IsAny<CancellationToken>()
                )
                .ReturnsAsync(new HttpResponseMessage
                {
                    StatusCode = statusCode,
                    Content = new StringContent(responseContent)
                });

            return new HttpClient(mockHandler.Object);
        }

        [Fact]
        public void Constructor_MissingEnvironmentVariable_ShouldThrowConfigurationException()
        {
            // Arrange
            Environment.SetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", null, EnvironmentVariableTarget.User);
            var httpClient = new HttpClient();

            // Act & Assert
            Assert.Throws<ConfigurationException>(() => new SearchService(httpClient, _mockLogger.Object));

            // Cleanup
            Environment.SetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", TestVectorPort, EnvironmentVariableTarget.User);
        }

        [Fact]
        public async Task SearchDocumentsAsync_SuccessfulSearch_ShouldReturnResults()
        {
            // Arrange
            var responseJson = JsonSerializer.Serialize(new DocumentSearchResponse
            {
                Success = true,
                Results = new[]
                {
                    new DocumentSearchResult
                    {
                        Id = "doc1",
                        Source = "test.txt",
                        Document = "content",
                        Similarity = 0.95m
                    }
                }
            });

            var httpClient = CreateMockHttpClient(HttpStatusCode.OK, responseJson);
            var service = new SearchService(httpClient, _mockLogger.Object);

            var request = new DocumentSearchRequest
            {
                Query = "test",
                CollectionName = "test-collection",
                Threshold = 0.6m,
                MaxResults = 5
            };

            // Act
            var result = await service.SearchDocumentsAsync(request);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("doc1", result.Results[0].Id);
        }

        [Fact]
        public async Task SearchDocumentsAsync_InvalidRequest_ShouldThrowArgumentException()
        {
            // Arrange
            var httpClient = new HttpClient();
            var service = new SearchService(httpClient, _mockLogger.Object);

            var request = new DocumentSearchRequest
            {
                Query = "", // Invalid: required field
                CollectionName = "test-collection"
            };

            // Act & Assert
            await Assert.ThrowsAsync<ArgumentException>(() => service.SearchDocumentsAsync(request));
        }

        [Fact]
        public async Task SearchDocumentsAsync_HttpError_ShouldThrowSearchException()
        {
            // Arrange
            var httpClient = CreateMockHttpClient(HttpStatusCode.InternalServerError, "Server Error");
            var service = new SearchService(httpClient, _mockLogger.Object);

            var request = new DocumentSearchRequest
            {
                Query = "test",
                CollectionName = "test-collection"
            };

            // Act & Assert
            await Assert.ThrowsAsync<SearchException>(() => service.SearchDocumentsAsync(request));
        }

        [Fact]
        public async Task SearchChunksAsync_WithAggregation_ShouldThrowInvalidAggregationModeException()
        {
            // Arrange
            var httpClient = new HttpClient();
            var service = new SearchService(httpClient, _mockLogger.Object);

            var request = new ChunkSearchRequest
            {
                Query = "test",
                CollectionName = "test-collection",
                AggregateByDocument = true // Invalid for SearchChunksAsync
            };

            // Act & Assert
            await Assert.ThrowsAsync<InvalidAggregationModeException>(() => service.SearchChunksAsync(request));
        }

        [Fact]
        public async Task SearchChunksAggregatedAsync_WithoutAggregation_ShouldThrowInvalidAggregationModeException()
        {
            // Arrange
            var httpClient = new HttpClient();
            var service = new SearchService(httpClient, _mockLogger.Object);

            var request = new ChunkSearchRequest
            {
                Query = "test",
                CollectionName = "test-collection",
                AggregateByDocument = false // Invalid for SearchChunksAggregatedAsync
            };

            // Act & Assert
            await Assert.ThrowsAsync<InvalidAggregationModeException>(() => service.SearchChunksAggregatedAsync(request));
        }

        [Fact]
        public async Task SearchChunksAsync_SuccessfulSearch_ShouldReturnResults()
        {
            // Arrange
            var responseJson = JsonSerializer.Serialize(new ChunkSearchResponse
            {
                Success = true,
                Results = new[]
                {
                    new ChunkSearchResult
                    {
                        Id = "chunk1",
                        Source = "test.txt",
                        Chunk = "chunk content",
                        Similarity = 0.88m,
                        Metadata = new ChunkMetadata { LineRange = "1-10" }
                    }
                }
            });

            var httpClient = CreateMockHttpClient(HttpStatusCode.OK, responseJson);
            var service = new SearchService(httpClient, _mockLogger.Object);

            var request = new ChunkSearchRequest
            {
                Query = "test",
                CollectionName = "test-collection",
                AggregateByDocument = false
            };

            // Act
            var result = await service.SearchChunksAsync(request);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("chunk1", result.Results[0].Id);
        }

        [Fact]
        public async Task SearchChunksAggregatedAsync_SuccessfulSearch_ShouldReturnAggregatedResults()
        {
            // Arrange
            var responseJson = JsonSerializer.Serialize(new ChunkAggregatedSearchResponse
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
                                Chunk = "content",
                                Similarity = 0.9m
                            }
                        }
                    }
                }
            });

            var httpClient = CreateMockHttpClient(HttpStatusCode.OK, responseJson);
            var service = new SearchService(httpClient, _mockLogger.Object);

            var request = new ChunkSearchRequest
            {
                Query = "test",
                CollectionName = "test-collection",
                AggregateByDocument = true
            };

            // Act
            var result = await service.SearchChunksAggregatedAsync(request);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("test.txt", result.Results[0].Source);
            Assert.Single(result.Results[0].Chunks);
        }
    }
}
