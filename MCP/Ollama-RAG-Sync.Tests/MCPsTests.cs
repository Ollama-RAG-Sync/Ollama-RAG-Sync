using System.Text.Json;

namespace ORSMcp.Tests
{
    public class MCPsTests
    {
        [Fact]
        public void LocalDocumentsSearch_WithDefaultParameters_ShouldReturnSerializedResponse()
        {
            // Arrange
            var mockHandler = new MockHttpMessageHandler();
            var responseData = new DocumentResponseData
            {
                Success = true,
                Results = new[]
                {
                    new DocumentResponseItemData
                    {
                        Id = "doc1",
                        Source = "test.txt",
                        Document = "test content",
                        Similarity = 0.95m
                    }
                }
            };
            mockHandler.ResponseContent = JsonSerializer.Serialize(responseData);
            var client = new HttpClient(mockHandler);

            // Set environment variable for the test
            Environment.SetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", "5000", EnvironmentVariableTarget.Process);

            // Act
            var result = MCPs.LocalDocumentsSearch(
                "test query",
                "test-collection",
                client,
                CancellationToken.None);

            // Assert
            Assert.NotNull(result);
            var deserializedResult = JsonSerializer.Deserialize<DocumentResponseData>(result);
            Assert.NotNull(deserializedResult);
            Assert.True(deserializedResult.Success);
            Assert.Single(deserializedResult.Results);
            Assert.Equal("doc1", deserializedResult.Results[0].Id);
        }

        [Fact]
        public void LocalDocumentsSearch_WithCustomParameters_ShouldUseProvidedValues()
        {
            // Arrange
            var mockHandler = new MockHttpMessageHandler();
            var responseData = new DocumentResponseData
            {
                Success = true,
                Results = Array.Empty<DocumentResponseItemData>()
            };
            mockHandler.ResponseContent = JsonSerializer.Serialize(responseData);
            var client = new HttpClient(mockHandler);

            Environment.SetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", "5000", EnvironmentVariableTarget.Process);

            // Act
            var result = MCPs.LocalDocumentsSearch(
                "custom query",
                "custom-collection",
                client,
                CancellationToken.None,
                threshold: 0.75m,
                maxResults: 10,
                returnDocument: false);

            // Assert
            Assert.NotNull(result);
            Assert.NotNull(mockHandler.LastRequest);
            var requestContent = mockHandler.LastRequestContent;
            Assert.Contains("\"threshold\":0.75", requestContent);
            Assert.Contains("\"max_results\":10", requestContent);
            Assert.Contains("return_content", requestContent);
        }

        [Fact]
        public void LocalChunksSearch_WithAggregationFalse_ShouldReturnChunkResponse()
        {
            // Arrange
            var mockHandler = new MockHttpMessageHandler();
            var responseData = new ChunkResponseData
            {
                Success = true,
                Results = new[]
                {
                    new ChunkResponseItemData
                    {
                        Id = "chunk1",
                        Source = "file.txt",
                        Document = "chunk content",
                        Metadata = new ChunkMetadata { LineRange = "1-10" },
                        Similarity = 0.88m
                    }
                }
            };
            mockHandler.ResponseContent = JsonSerializer.Serialize(responseData);
            var client = new HttpClient(mockHandler);

            Environment.SetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", "5000", EnvironmentVariableTarget.Process);

            // Act
            var result = MCPs.LocalChunksSearch(
                "test query",
                "test-collection",
                client,
                CancellationToken.None,
                aggregateByDocument: false);

            // Assert
            Assert.NotNull(result);
            var deserializedResult = JsonSerializer.Deserialize<ChunkResponseData>(result);
            Assert.NotNull(deserializedResult);
            Assert.True(deserializedResult.Success);
            Assert.Single(deserializedResult.Results);
            Assert.Equal("chunk1", deserializedResult.Results[0].Id);
        }

        [Fact]
        public void LocalChunksSearch_WithAggregationTrue_ShouldReturnAggregatedResponse()
        {
            // Arrange
            var mockHandler = new MockHttpMessageHandler();
            var responseData = new ChunkAggregatedResponseData
            {
                Success = true,
                Results = new[]
                {
                    new ChunkAggregatedResponseItemData
                    {
                        Source = "document.txt",
                        Chunks = new[]
                        {
                            new ChunkResponseItemData
                            {
                                Id = "chunk1",
                                Source = "document.txt",
                                Document = "content",
                                Metadata = new ChunkMetadata { LineRange = "1-5" },
                                Similarity = 0.9m
                            }
                        }
                    }
                }
            };
            mockHandler.ResponseContent = JsonSerializer.Serialize(responseData);
            var client = new HttpClient(mockHandler);

            Environment.SetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", "5000", EnvironmentVariableTarget.Process);

            // Act
            var result = MCPs.LocalChunksSearch(
                "test query",
                "test-collection",
                client,
                CancellationToken.None,
                aggregateByDocument: true);

            // Assert
            Assert.NotNull(result);
            var deserializedResult = JsonSerializer.Deserialize<ChunkAggregatedResponseData>(result);
            Assert.NotNull(deserializedResult);
            Assert.True(deserializedResult.Success);
            Assert.Single(deserializedResult.Results);
            Assert.Equal("document.txt", deserializedResult.Results[0].Source);
        }
    }

    // Mock HTTP message handler for testing
    public class MockHttpMessageHandler : HttpMessageHandler
    {
        public string ResponseContent { get; set; } = "{}";
        public HttpStatusCode StatusCode { get; set; } = HttpStatusCode.OK;
        public HttpRequestMessage? LastRequest { get; private set; }
        public string LastRequestContent { get; private set; } = string.Empty;

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            LastRequest = request;
            if (request.Content != null)
            {
                LastRequestContent = await request.Content.ReadAsStringAsync(cancellationToken);
            }

            return new HttpResponseMessage
            {
                StatusCode = StatusCode,
                Content = new StringContent(ResponseContent)
            };
        }
    }
}
