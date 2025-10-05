using Microsoft.Extensions.Logging;
using ORSMcp.Exceptions;
using ORSMcp.Extensions;
using ORSMcp.Models;
using System.ComponentModel.DataAnnotations;

namespace ORSMcp.Services
{
    /// <summary>
    /// Implements search operations for documents and chunks using the RAG vector API.
    /// </summary>
    public class SearchService : ISearchService
    {
        private readonly HttpClient _httpClient;
        private readonly ILogger<SearchService> _logger;
        private readonly string _vectorsApiUrl;

        /// <summary>
        /// Initializes a new instance of the <see cref="SearchService"/> class.
        /// </summary>
        /// <param name="httpClient">The HTTP client for making API requests.</param>
        /// <param name="logger">The logger instance.</param>
        /// <exception cref="ConfigurationException">Thrown when required configuration is missing.</exception>
        public SearchService(HttpClient httpClient, ILogger<SearchService> logger)
        {
            _httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));

            var vectorPort = Environment.GetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", EnvironmentVariableTarget.User);
            if (string.IsNullOrWhiteSpace(vectorPort))
            {
                throw new ConfigurationException(
                    "OLLAMA_RAG_VECTORS_API_PORT environment variable is not set. " +
                    "Please run Setup-RAG.ps1 to configure the environment.");
            }

            _vectorsApiUrl = $"http://localhost:{vectorPort}";
            _logger.LogInformation("SearchService initialized with Vectors API URL: {ApiUrl}", _vectorsApiUrl);
        }

        /// <inheritdoc/>
        public async Task<DocumentSearchResponse> SearchDocumentsAsync(
            DocumentSearchRequest request,
            CancellationToken cancellationToken = default)
        {
            ValidateRequest(request);

            _logger.LogInformation(
                "Searching documents: Query='{Query}', Collection='{Collection}', Threshold={Threshold}, MaxResults={MaxResults}",
                request.Query, request.CollectionName, request.Threshold, request.MaxResults);

            try
            {
                var url = $"{_vectorsApiUrl}/api/search/documents";
                var response = await _httpClient.PostAsJsonAsync(url, request, cancellationToken);

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync(cancellationToken);
                    throw new SearchException(
                        $"Document search failed with status code {response.StatusCode}: {errorContent}");
                }

                var result = await response.Content.ReadFromJsonAsync<DocumentSearchResponse>(cancellationToken);
                
                if (result == null)
                {
                    throw new SearchException("Failed to deserialize document search response.");
                }

                _logger.LogInformation(
                    "Document search completed: Found {Count} results",
                    result.Results?.Length ?? 0);

                return result;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP error during document search");
                throw new SearchException("Failed to communicate with the Vectors API. Ensure the service is running.", ex);
            }
            catch (SearchException)
            {
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error during document search");
                throw new SearchException("An unexpected error occurred during document search.", ex);
            }
        }

        /// <inheritdoc/>
        public async Task<ChunkSearchResponse> SearchChunksAsync(
            ChunkSearchRequest request,
            CancellationToken cancellationToken = default)
        {
            ValidateRequest(request);

            if (request.AggregateByDocument)
            {
                throw new InvalidAggregationModeException(false);
            }

            _logger.LogInformation(
                "Searching chunks: Query='{Query}', Collection='{Collection}', Threshold={Threshold}, MaxResults={MaxResults}",
                request.Query, request.CollectionName, request.Threshold, request.MaxResults);

            try
            {
                var url = $"{_vectorsApiUrl}/api/search/chunks";
                var response = await _httpClient.PostAsJsonAsync(url, request, cancellationToken);

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync(cancellationToken);
                    throw new SearchException(
                        $"Chunk search failed with status code {response.StatusCode}: {errorContent}");
                }

                var result = await response.Content.ReadFromJsonAsync<ChunkSearchResponse>(cancellationToken);
                
                if (result == null)
                {
                    throw new SearchException("Failed to deserialize chunk search response.");
                }

                _logger.LogInformation(
                    "Chunk search completed: Found {Count} results",
                    result.Results?.Length ?? 0);

                return result;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP error during chunk search");
                throw new SearchException("Failed to communicate with the Vectors API. Ensure the service is running.", ex);
            }
            catch (SearchException)
            {
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error during chunk search");
                throw new SearchException("An unexpected error occurred during chunk search.", ex);
            }
        }

        /// <inheritdoc/>
        public async Task<ChunkAggregatedSearchResponse> SearchChunksAggregatedAsync(
            ChunkSearchRequest request,
            CancellationToken cancellationToken = default)
        {
            ValidateRequest(request);

            if (!request.AggregateByDocument)
            {
                throw new InvalidAggregationModeException(true);
            }

            _logger.LogInformation(
                "Searching chunks (aggregated): Query='{Query}', Collection='{Collection}', Threshold={Threshold}, MaxResults={MaxResults}",
                request.Query, request.CollectionName, request.Threshold, request.MaxResults);

            try
            {
                var url = $"{_vectorsApiUrl}/api/search/chunks";
                var response = await _httpClient.PostAsJsonAsync(url, request, cancellationToken);

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync(cancellationToken);
                    throw new SearchException(
                        $"Aggregated chunk search failed with status code {response.StatusCode}: {errorContent}");
                }

                var result = await response.Content.ReadFromJsonAsync<ChunkAggregatedSearchResponse>(cancellationToken);
                
                if (result == null)
                {
                    throw new SearchException("Failed to deserialize aggregated chunk search response.");
                }

                _logger.LogInformation(
                    "Aggregated chunk search completed: Found {Count} documents",
                    result.Results?.Length ?? 0);

                return result;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP error during aggregated chunk search");
                throw new SearchException("Failed to communicate with the Vectors API. Ensure the service is running.", ex);
            }
            catch (SearchException)
            {
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error during aggregated chunk search");
                throw new SearchException("An unexpected error occurred during aggregated chunk search.", ex);
            }
        }

        private void ValidateRequest<T>(T request) where T : class
        {
            var validationContext = new ValidationContext(request);
            var validationResults = new List<ValidationResult>();

            if (!Validator.TryValidateObject(request, validationContext, validationResults, true))
            {
                var errors = string.Join("; ", validationResults.Select(r => r.ErrorMessage));
                throw new ArgumentException($"Invalid request: {errors}");
            }
        }
    }
}
