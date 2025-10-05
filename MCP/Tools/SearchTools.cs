using Microsoft.Extensions.Logging;
using ModelContextProtocol.Server;
using ORSMcp.Exceptions;
using ORSMcp.Models;
using ORSMcp.Services;
using System.ComponentModel;
using System.Text.Json;

namespace ORSMcp.Tools
{
    /// <summary>
    /// Provides MCP tools for local document and chunk search operations.
    /// </summary>
    [McpServerToolType]
    public class SearchTools
    {
        private readonly ISearchService _searchService;
        private readonly ILogger<SearchTools> _logger;

        /// <summary>
        /// Initializes a new instance of the <see cref="SearchTools"/> class.
        /// </summary>
        /// <param name="searchService">The search service.</param>
        /// <param name="logger">The logger instance.</param>
        public SearchTools(ISearchService searchService, ILogger<SearchTools> logger)
        {
            _searchService = searchService ?? throw new ArgumentNullException(nameof(searchService));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        /// <summary>
        /// Finds the best documents in the local document collection based on vector similarity search.
        /// </summary>
        /// <param name="prompt">The search query text.</param>
        /// <param name="collectionName">The name of the document collection to search.</param>
        /// <param name="cancellationToken">Cancellation token for the operation.</param>
        /// <param name="threshold">Similarity threshold (0.0 to 1.0). Documents below this threshold are filtered out.</param>
        /// <param name="maxResults">Maximum number of results to return.</param>
        /// <param name="returnDocument">Whether to include full document content in results.</param>
        /// <returns>JSON string containing the search results.</returns>
        [McpServerTool(Name = "localDocumentsSearch")]
        [Description("Finds the best documents in the local document collection (best matches) based on vector similarity search.")]
        public async Task<string> LocalDocumentsSearch(
            string prompt,
            string collectionName,
            CancellationToken cancellationToken,
            [Description("Threshold of similarity of documents to return (0.0-1.0)")] decimal threshold = 0.6m,
            int maxResults = 2,
            bool returnDocument = true)
        {
            try
            {
                _logger.LogInformation(
                    "LocalDocumentsSearch called: Prompt='{Prompt}', Collection='{Collection}'",
                    prompt, collectionName);

                var request = new DocumentSearchRequest
                {
                    Query = prompt,
                    CollectionName = collectionName,
                    Threshold = threshold,
                    MaxResults = maxResults,
                    ReturnContent = returnDocument
                };

                var response = await _searchService.SearchDocumentsAsync(request, cancellationToken);
                
                return JsonSerializer.Serialize(response);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in LocalDocumentsSearch");
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = ex.Message,
                    errorType = ex.GetType().Name
                });
            }
        }

        /// <summary>
        /// Finds the best chunks in the local document collection based on vector similarity search.
        /// </summary>
        /// <param name="prompt">The search query text.</param>
        /// <param name="collectionName">The name of the document collection to search.</param>
        /// <param name="cancellationToken">Cancellation token for the operation.</param>
        /// <param name="threshold">Similarity threshold (0.0 to 1.0). Chunks below this threshold are filtered out.</param>
        /// <param name="maxResults">Maximum number of results to return.</param>
        /// <param name="aggregateByDocument">Whether to aggregate chunks by their source document.</param>
        /// <returns>JSON string containing the search results.</returns>
        [McpServerTool(Name = "localChunksSearch")]
        [Description("Finds the best chunks in the local document collection (best matches) based on vector similarity search")]
        public async Task<string> LocalChunksSearch(
            string prompt,
            string collectionName,
            CancellationToken cancellationToken,
            [Description("Threshold of similarity of chunks to return (0.0-1.0)")] decimal threshold = 0.6m,
            int maxResults = 2,
            bool aggregateByDocument = false)
        {
            try
            {
                _logger.LogInformation(
                    "LocalChunksSearch called: Prompt='{Prompt}', Collection='{Collection}', Aggregate={Aggregate}",
                    prompt, collectionName, aggregateByDocument);

                var request = new ChunkSearchRequest
                {
                    Query = prompt,
                    CollectionName = collectionName,
                    Threshold = threshold,
                    MaxResults = maxResults,
                    AggregateByDocument = aggregateByDocument
                };

                if (aggregateByDocument)
                {
                    var response = await _searchService.SearchChunksAggregatedAsync(request, cancellationToken);
                    return JsonSerializer.Serialize(response);
                }
                else
                {
                    var response = await _searchService.SearchChunksAsync(request, cancellationToken);
                    return JsonSerializer.Serialize(response);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in LocalChunksSearch");
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = ex.Message,
                    errorType = ex.GetType().Name
                });
            }
        }
    }
}
