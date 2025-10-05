using Moq;
using Moq.Protected;
using ORSMcp.Models;
using System.Net;
using System.Text.Json;

namespace ORSMcp.Tests
{
    /// <summary>
    /// Tests for backward compatibility - these test the old class names that are now replaced.
    /// New tests are in Services/SearchServiceTests.cs and Models/ModelValidationTests.cs
    /// </summary>
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
        public async Task DocumentSearchRequest_SuccessfulResponse_ShouldDeserialize()
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

            // Act
            var response = await client.GetAsync("http://test.com/api");
            var content = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<DocumentSearchResponse>(content);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("doc1", result.Results[0].Id);
            Assert.Equal("test.txt", result.Results[0].Source);
            Assert.Equal(0.95m, result.Results[0].Similarity);
        }

        [Fact]
        public async Task ChunkSearchResponse_SuccessfulResponse_ShouldDeserialize()
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

            // Act
            var response = await client.GetAsync("http://test.com/api");
            var content = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<ChunkSearchResponse>(content);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("chunk1", result.Results[0].Id);
            Assert.Equal("file.txt", result.Results[0].Source);
            Assert.Equal(0.88m, result.Results[0].Similarity);
        }

        [Fact]
        public async Task ChunkAggregatedSearchResponse_SuccessfulResponse_ShouldDeserialize()
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

            // Act
            var response = await client.GetAsync("http://test.com/api");
            var content = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<ChunkAggregatedSearchResponse>(content);

            // Assert
            Assert.NotNull(result);
            Assert.True(result.Success);
            Assert.Single(result.Results);
            Assert.Equal("document.txt", result.Results[0].Source);
            Assert.Single(result.Results[0].Chunks);
            Assert.Equal("chunk1", result.Results[0].Chunks[0].Id);
        }

        [Fact]
        public void DocumentSearchRequest_Validation_ShouldWork()
        {
            // Arrange & Act
            var request = new DocumentSearchRequest
            {
                Query = "test",
                CollectionName = "collection",
                Threshold = 0.7m,
                MaxResults = 5
            };

            // Assert
            Assert.Equal("test", request.Query);
            Assert.Equal("collection", request.CollectionName);
            Assert.Equal(0.7m, request.Threshold);
            Assert.Equal(5, request.MaxResults);
        }

        [Fact]
        public void ChunkSearchRequest_Validation_ShouldWork()
        {
            // Arrange & Act
            var request = new ChunkSearchRequest
            {
                Query = "test",
                CollectionName = "collection",
                Threshold = 0.6m,
                MaxResults = 10,
                AggregateByDocument = true
            };

            // Assert
            Assert.Equal("test", request.Query);
            Assert.Equal("collection", request.CollectionName);
            Assert.Equal(0.6m, request.Threshold);
            Assert.Equal(10, request.MaxResults);
            Assert.True(request.AggregateByDocument);
        }
    }
}
