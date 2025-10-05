using ORSMcp.Models;
using System.Net;
using System.Text.Json;

namespace ORSMcp.Tests
{
    public class RequestDataTests
    {
        [Fact]
        public void RequestData_Serialization_ShouldUseCorrectPropertyNames()
        {
            // Arrange
            var requestData = new DocumentSearchRequest
            {
                Query = "test query",
                Threshold = 0.8m,
                MaxResults = 5,
                ReturnContent = true,
                CollectionName = "test-collection"
            };

            // Act
            var json = JsonSerializer.Serialize(requestData);
            var deserialized = JsonSerializer.Deserialize<DocumentSearchRequest>(json);

            // Assert
            Assert.NotNull(deserialized);
            Assert.Equal(requestData.Query, deserialized.Query);
            Assert.Equal(requestData.Threshold, deserialized.Threshold);
            Assert.Equal(requestData.MaxResults, deserialized.MaxResults);
            Assert.Equal(requestData.ReturnContent, deserialized.ReturnContent);
            Assert.Equal(requestData.CollectionName, deserialized.CollectionName);
        }

        [Fact]
        public void RequestData_JsonSerialization_ShouldHaveCorrectPropertyNames()
        {
            // Arrange
            var requestData = new DocumentSearchRequest
            {
                Query = "test",
                Threshold = 0.5m,
                MaxResults = 10,
                ReturnContent = false,
                CollectionName = "collection"
            };

            // Act
            var json = JsonSerializer.Serialize(requestData);

            // Assert
            Assert.Contains("\"query\":", json);
            Assert.Contains("\"threshold\":", json);
            Assert.Contains("\"max_results\":", json);
            Assert.Contains("\"return_content\":", json);
            Assert.Contains("\"collectionName\":", json);
        }
    }

    public class ChunkRequestDataTests
    {
        [Fact]
        public void ChunkRequestData_Serialization_ShouldUseCorrectPropertyNames()
        {
            // Arrange
            var requestData = new ChunkSearchRequest
            {
                Query = "test query",
                Threshold = 0.7m,
                AggregateByDocument = true,
                MaxResults = 3,
                CollectionName = "chunk-collection"
            };

            // Act
            var json = JsonSerializer.Serialize(requestData);
            var deserialized = JsonSerializer.Deserialize<ChunkSearchRequest>(json);

            // Assert
            Assert.NotNull(deserialized);
            Assert.Equal(requestData.Query, deserialized.Query);
            Assert.Equal(requestData.Threshold, deserialized.Threshold);
            Assert.Equal(requestData.AggregateByDocument, deserialized.AggregateByDocument);
            Assert.Equal(requestData.MaxResults, deserialized.MaxResults);
            Assert.Equal(requestData.CollectionName, deserialized.CollectionName);
        }

        [Fact]
        public void ChunkRequestData_JsonSerialization_ShouldHaveCorrectPropertyNames()
        {
            // Arrange
            var requestData = new ChunkSearchRequest
            {
                Query = "test",
                Threshold = 0.5m,
                AggregateByDocument = false,
                MaxResults = 5,
                CollectionName = "collection"
            };

            // Act
            var json = JsonSerializer.Serialize(requestData);

            // Assert
            Assert.Contains("\"query\":", json);
            Assert.Contains("\"threshold\":", json);
            Assert.Contains("\"aggregateByDocument\":", json);
            Assert.Contains("\"max_results\":", json);
            Assert.Contains("\"collectionName\":", json);
        }
    }

    public class DocumentResponseDataTests
    {
        [Fact]
        public void DocumentResponseData_Deserialization_ShouldWorkCorrectly()
        {
            // Arrange
            var json = @"{
                ""success"": true,
                ""results"": [
                    {
                        ""id"": ""doc1"",
                        ""source"": ""source1.txt"",
                        ""document"": ""content1"",
                        ""similarity"": 0.95
                    },
                    {
                        ""id"": ""doc2"",
                        ""source"": ""source2.txt"",
                        ""document"": ""content2"",
                        ""similarity"": 0.85
                    }
                ]
            }";

            // Act
            var response = JsonSerializer.Deserialize<DocumentSearchResponse>(json);

            // Assert
            Assert.NotNull(response);
            Assert.True(response.Success);
            Assert.NotNull(response.Results);
            Assert.Equal(2, response.Results.Length);
            Assert.Equal("doc1", response.Results[0].Id);
            Assert.Equal("source1.txt", response.Results[0].Source);
            Assert.Equal("content1", response.Results[0].Document);
            Assert.Equal(0.95m, response.Results[0].Similarity);
        }

        [Fact]
        public void DocumentResponseData_EmptyResults_ShouldWorkCorrectly()
        {
            // Arrange
            var json = @"{""success"": true, ""results"": []}";

            // Act
            var response = JsonSerializer.Deserialize<DocumentSearchResponse>(json);

            // Assert
            Assert.NotNull(response);
            Assert.True(response.Success);
            Assert.NotNull(response.Results);
            Assert.Empty(response.Results);
        }
    }

    public class ChunkResponseDataTests
    {
        [Fact]
        public void ChunkResponseData_Deserialization_ShouldWorkCorrectly()
        {
            // Arrange
            var json = @"{
                ""success"": true,
                ""results"": [
                    {
                        ""id"": ""chunk1"",
                        ""source"": ""file1.txt"",
                        ""chunk"": ""chunk content 1"",
                        ""metadata"": {
                            ""line_range"": ""1-10""
                        },
                        ""similarity"": 0.92
                    }
                ]
            }";

            // Act
            var response = JsonSerializer.Deserialize<ChunkSearchResponse>(json);

            // Assert
            Assert.NotNull(response);
            Assert.True(response.Success);
            Assert.NotNull(response.Results);
            Assert.Single(response.Results);
            Assert.Equal("chunk1", response.Results[0].Id);
            Assert.Equal("file1.txt", response.Results[0].Source);
            Assert.Equal("chunk content 1", response.Results[0].Chunk);
            Assert.Equal("1-10", response.Results[0].Metadata.LineRange);
            Assert.Equal(0.92m, response.Results[0].Similarity);
        }
    }
}
