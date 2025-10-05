using Moq;
using Moq.Protected;
using System.Net;
using System.Text.Json;

namespace ORSMcp.Tests
{
    public class HttpClientExtTests
    {
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
        public async Task ReadJsonDocumentsAsync_SuccessfulResponse_ShouldReturnDocumentResponseData()
        {
            // Arrange
            var responseJson = @"{
                ""success"": true,
                ""results"": [
                    {
                        ""id"": ""doc1"",
                        ""source"": ""test.txt"",
                        ""document"": ""test content"",
                        ""similarity"": 0.95
                    }
                ]
            }";
            var client = CreateMockHttpClient(HttpStatusCode.OK, responseJson);
            var request = new RequestData
            {
                Query = "test query",
                Threshold = 0.8m,
                MaxResults = 5,
                ReturnContent = true,
                CollectionName = "test-collection"
            };

            // Act
            var result = await client.ReadJsonDocumentsAsync(request, "http://test.com/api", CancellationToken.None);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("doc1", result.Results[0].Id);
            Assert.Equal("test.txt", result.Results[0].Source);
            Assert.Equal(0.95m, result.Results[0].Similarity);
        }

        [Fact]
        public async Task ReadJsonDocumentsAsync_NonSuccessStatusCode_ShouldThrowHttpRequestException()
        {
            // Arrange
            var client = CreateMockHttpClient(HttpStatusCode.InternalServerError, "Error");
            var request = new RequestData
            {
                Query = "test query",
                Threshold = 0.8m,
                MaxResults = 5,
                ReturnContent = true,
                CollectionName = "test-collection"
            };

            // Act & Assert
            await Assert.ThrowsAsync<HttpRequestException>(async () =>
                await client.ReadJsonDocumentsAsync(request, "http://test.com/api", CancellationToken.None));
        }

        [Fact]
        public async Task ReadJsonChunksAsync_SuccessfulResponse_ShouldReturnChunkResponseData()
        {
            // Arrange
            var responseJson = @"{
                ""success"": true,
                ""results"": [
                    {
                        ""id"": ""chunk1"",
                        ""source"": ""file.txt"",
                        ""chunk"": ""chunk content"",
                        ""metadata"": {
                            ""line_range"": ""1-10""
                        },
                        ""similarity"": 0.88
                    }
                ]
            }";
            var client = CreateMockHttpClient(HttpStatusCode.OK, responseJson);
            var request = new ChunkRequestData
            {
                Query = "test query",
                Threshold = 0.7m,
                AggregateByDocument = false,
                MaxResults = 3,
                CollectionName = "test-collection"
            };

            // Act
            var result = await client.ReadJsonChunksAsync(request, "http://test.com/api", CancellationToken.None);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("chunk1", result.Results[0].Id);
            Assert.Equal("file.txt", result.Results[0].Source);
            Assert.Equal(0.88m, result.Results[0].Similarity);
        }

        [Fact]
        public async Task ReadJsonChunksAsync_AggregateByDocumentTrue_ShouldThrowException()
        {
            // Arrange
            var client = CreateMockHttpClient(HttpStatusCode.OK, "{}");
            var request = new ChunkRequestData
            {
                Query = "test query",
                Threshold = 0.7m,
                AggregateByDocument = true,
                MaxResults = 3,
                CollectionName = "test-collection"
            };

            // Act & Assert
            var exception = await Assert.ThrowsAsync<Exception>(async () =>
                await client.ReadJsonChunksAsync(request, "http://test.com/api", CancellationToken.None));
            Assert.Contains("AggregateByDocument must be false", exception.Message);
        }

        [Fact]
        public async Task ReadJsonChunksAggregatedAsync_SuccessfulResponse_ShouldReturnAggregatedData()
        {
            // Arrange
            var responseJson = @"{
                ""success"": true,
                ""results"": [
                    {
                        ""source"": ""document.txt"",
                        ""chunks"": [
                            {
                                ""id"": ""chunk1"",
                                ""source"": ""document.txt"",
                                ""chunk"": ""content"",
                                ""metadata"": {
                                    ""line_range"": ""1-5""
                                },
                                ""similarity"": 0.9
                            }
                        ]
                    }
                ]
            }";
            var client = CreateMockHttpClient(HttpStatusCode.OK, responseJson);
            var request = new ChunkRequestData
            {
                Query = "test query",
                Threshold = 0.7m,
                AggregateByDocument = true,
                MaxResults = 3,
                CollectionName = "test-collection"
            };

            // Act
            var result = await client.ReadJsonChunksAggregatedAsync(request, "http://test.com/api", CancellationToken.None);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("document.txt", result.Results[0].Source);
            Assert.Single(result.Results[0].Chunks);
            Assert.Equal("chunk1", result.Results[0].Chunks[0].Id);
        }

        [Fact]
        public async Task ReadJsonChunksAggregatedAsync_AggregateByDocumentFalse_ShouldThrowException()
        {
            // Arrange
            var client = CreateMockHttpClient(HttpStatusCode.OK, "{}");
            var request = new ChunkRequestData
            {
                Query = "test query",
                Threshold = 0.7m,
                AggregateByDocument = false,
                MaxResults = 3,
                CollectionName = "test-collection"
            };

            // Act & Assert
            var exception = await Assert.ThrowsAsync<Exception>(async () =>
                await client.ReadJsonChunksAggregatedAsync(request, "http://test.com/api", CancellationToken.None));
            Assert.Contains("AggregateByDocument must be true", exception.Message);
        }

        [Fact]
        public async Task ReadJsonChunksAsync_NonSuccessStatusCode_ShouldThrowHttpRequestException()
        {
            // Arrange
            var client = CreateMockHttpClient(HttpStatusCode.BadRequest, "Bad Request");
            var request = new ChunkRequestData
            {
                Query = "test query",
                Threshold = 0.7m,
                AggregateByDocument = false,
                MaxResults = 3,
                CollectionName = "test-collection"
            };

            // Act & Assert
            await Assert.ThrowsAsync<HttpRequestException>(async () =>
                await client.ReadJsonChunksAsync(request, "http://test.com/api", CancellationToken.None));
        }
    }
}
