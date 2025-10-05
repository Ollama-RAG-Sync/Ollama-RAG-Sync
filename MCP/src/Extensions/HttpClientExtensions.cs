using System.Net.Http.Json;
using System.Text.Json;

namespace ORSMcp.Extensions
{
    /// <summary>
    /// Extension methods for HttpClient to simplify JSON operations.
    /// </summary>
    public static class HttpClientExtensions
    {
        private static readonly JsonSerializerOptions DefaultJsonOptions = new()
        {
            PropertyNameCaseInsensitive = true,
            WriteIndented = false
        };

        /// <summary>
        /// Sends a POST request with JSON content.
        /// </summary>
        /// <typeparam name="T">The type of the request object.</typeparam>
        /// <param name="client">The HTTP client.</param>
        /// <param name="requestUri">The request URI.</param>
        /// <param name="content">The content to serialize as JSON.</param>
        /// <param name="cancellationToken">Cancellation token for the operation.</param>
        /// <returns>The HTTP response message.</returns>
        public static Task<HttpResponseMessage> PostAsJsonAsync<T>(
            this HttpClient client,
            string requestUri,
            T content,
            CancellationToken cancellationToken = default)
        {
            return client.PostAsJsonAsync(requestUri, content, DefaultJsonOptions, cancellationToken);
        }

        /// <summary>
        /// Reads the response content as JSON and deserializes it.
        /// </summary>
        /// <typeparam name="T">The type to deserialize to.</typeparam>
        /// <param name="content">The HTTP content.</param>
        /// <param name="cancellationToken">Cancellation token for the operation.</param>
        /// <returns>The deserialized object.</returns>
        public static Task<T?> ReadFromJsonAsync<T>(
            this HttpContent content,
            CancellationToken cancellationToken = default)
        {
            return content.ReadFromJsonAsync<T>(DefaultJsonOptions, cancellationToken);
        }
    }
}
