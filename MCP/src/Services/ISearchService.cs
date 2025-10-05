using ORSMcp.Models;

namespace ORSMcp.Services
{
    /// <summary>
    /// Defines the contract for document and chunk search operations.
    /// </summary>
    public interface ISearchService
    {
        /// <summary>
        /// Searches for documents based on semantic similarity.
        /// </summary>
        /// <param name="request">The search request parameters.</param>
        /// <param name="cancellationToken">Cancellation token for the operation.</param>
        /// <returns>A task that represents the asynchronous operation. The task result contains the search response.</returns>
        Task<DocumentSearchResponse> SearchDocumentsAsync(
            DocumentSearchRequest request,
            CancellationToken cancellationToken = default);

        /// <summary>
        /// Searches for text chunks based on semantic similarity.
        /// </summary>
        /// <param name="request">The search request parameters.</param>
        /// <param name="cancellationToken">Cancellation token for the operation.</param>
        /// <returns>A task that represents the asynchronous operation. The task result contains the search response.</returns>
        Task<ChunkSearchResponse> SearchChunksAsync(
            ChunkSearchRequest request,
            CancellationToken cancellationToken = default);

        /// <summary>
        /// Searches for text chunks and aggregates them by source document.
        /// </summary>
        /// <param name="request">The search request parameters with AggregateByDocument set to true.</param>
        /// <param name="cancellationToken">Cancellation token for the operation.</param>
        /// <returns>A task that represents the asynchronous operation. The task result contains the aggregated search response.</returns>
        Task<ChunkAggregatedSearchResponse> SearchChunksAggregatedAsync(
            ChunkSearchRequest request,
            CancellationToken cancellationToken = default);
    }
}
