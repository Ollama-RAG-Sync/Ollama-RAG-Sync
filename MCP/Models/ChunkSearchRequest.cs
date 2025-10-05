using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace ORSMcp.Models
{
    /// <summary>
    /// Represents a request to search for text chunks based on semantic similarity.
    /// </summary>
    public class ChunkSearchRequest
    {
        /// <summary>
        /// Gets or sets the search query text.
        /// </summary>
        [Required]
        [JsonPropertyName("query")]
        public string Query { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the similarity threshold (0.0 to 1.0).
        /// Chunks with similarity below this value will be filtered out.
        /// </summary>
        [Range(0.0, 1.0)]
        [JsonPropertyName("threshold")]
        public decimal Threshold { get; set; } = 0.6m;

        /// <summary>
        /// Gets or sets whether to aggregate results by source document.
        /// </summary>
        [JsonPropertyName("aggregateByDocument")]
        public bool AggregateByDocument { get; set; } = false;

        /// <summary>
        /// Gets or sets the maximum number of results to return.
        /// </summary>
        [Range(1, 1000)]
        [JsonPropertyName("max_results")]
        public int MaxResults { get; set; } = 5;

        /// <summary>
        /// Gets or sets the name of the document collection to search.
        /// </summary>
        [Required]
        [JsonPropertyName("collectionName")]
        public string CollectionName { get; set; } = string.Empty;
    }
}
