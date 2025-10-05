using System.Text.Json.Serialization;

namespace ORSMcp.Models
{
    /// <summary>
    /// Represents a response containing document search results.
    /// </summary>
    public class DocumentSearchResponse
    {
        /// <summary>
        /// Gets or sets whether the search operation was successful.
        /// </summary>
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        /// <summary>
        /// Gets or sets the array of matching documents.
        /// </summary>
        [JsonPropertyName("results")]
        public DocumentSearchResult[] Results { get; set; } = Array.Empty<DocumentSearchResult>();
    }

    /// <summary>
    /// Represents a single document search result.
    /// </summary>
    public class DocumentSearchResult
    {
        /// <summary>
        /// Gets or sets the unique identifier of the document.
        /// </summary>
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the source file path of the document.
        /// </summary>
        [JsonPropertyName("source")]
        public string Source { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the document content.
        /// </summary>
        [JsonPropertyName("document")]
        public string Document { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the similarity score (0.0 to 1.0).
        /// </summary>
        [JsonPropertyName("similarity")]
        public decimal Similarity { get; set; }
    }
}
