using System.Text.Json.Serialization;

namespace ORSMcp.Models
{
    /// <summary>
    /// Represents a response containing chunk search results.
    /// </summary>
    public class ChunkSearchResponse
    {
        /// <summary>
        /// Gets or sets whether the search operation was successful.
        /// </summary>
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        /// <summary>
        /// Gets or sets the array of matching chunks.
        /// </summary>
        [JsonPropertyName("results")]
        public ChunkSearchResult[] Results { get; set; } = Array.Empty<ChunkSearchResult>();
    }

    /// <summary>
    /// Represents a single chunk search result.
    /// </summary>
    public class ChunkSearchResult
    {
        /// <summary>
        /// Gets or sets the unique identifier of the chunk.
        /// </summary>
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the source file path of the chunk.
        /// </summary>
        [JsonPropertyName("source")]
        public string Source { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the chunk content.
        /// </summary>
        [JsonPropertyName("chunk")]
        public string Chunk { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets metadata about the chunk.
        /// </summary>
        [JsonPropertyName("metadata")]
        public ChunkMetadata? Metadata { get; set; }

        /// <summary>
        /// Gets or sets the similarity score (0.0 to 1.0).
        /// </summary>
        [JsonPropertyName("similarity")]
        public decimal Similarity { get; set; }
    }

    /// <summary>
    /// Represents metadata associated with a text chunk.
    /// </summary>
    public class ChunkMetadata
    {
        /// <summary>
        /// Gets or sets the line range in the source document (e.g., "10-25").
        /// </summary>
        [JsonPropertyName("line_range")]
        public string LineRange { get; set; } = string.Empty;
    }

    /// <summary>
    /// Represents a response containing aggregated chunk search results grouped by document.
    /// </summary>
    public class ChunkAggregatedSearchResponse
    {
        /// <summary>
        /// Gets or sets whether the search operation was successful.
        /// </summary>
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        /// <summary>
        /// Gets or sets the array of aggregated results by document.
        /// </summary>
        [JsonPropertyName("results")]
        public AggregatedChunkResult[] Results { get; set; } = Array.Empty<AggregatedChunkResult>();
    }

    /// <summary>
    /// Represents chunks aggregated by their source document.
    /// </summary>
    public class AggregatedChunkResult
    {
        /// <summary>
        /// Gets or sets the source file path.
        /// </summary>
        [JsonPropertyName("source")]
        public string Source { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the chunks from this source document.
        /// </summary>
        [JsonPropertyName("chunks")]
        public ChunkSearchResult[] Chunks { get; set; } = Array.Empty<ChunkSearchResult>();
    }
}
