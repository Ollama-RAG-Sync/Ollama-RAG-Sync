using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Protocol.Types;
using ModelContextProtocol.Server;
using System.ComponentModel;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ORSMcp
{
    internal class Program
    {
        static async Task Main(string[] args)
        {
            var builder = Host.CreateApplicationBuilder(args);
            builder.Logging.AddConsole(consoleLogOptions =>
            {
                // Configure all logs to go to stderr
                consoleLogOptions.LogToStandardErrorThreshold = LogLevel.Trace;
            });

            builder.Services
                .AddMcpServer()
                .WithStdioServerTransport()
                .WithToolsFromAssembly();

            builder.Services.AddSingleton(_ =>
            {
                var client = new HttpClient();
                return client;
            });

            await builder.Build().RunAsync();

        }
    }
}

// Define a class for your data payload
public class RequestData
{
    [JsonPropertyName("query")]
    public string Query { get; set; }

    [JsonPropertyName("threshold")]
    public decimal Threshold { get; set; }

    [JsonPropertyName("max_results")]
    public int MaxResults { get; set; }

    [JsonPropertyName("return_content")]
    public bool ReturContent { get; set; }
}


public class ChunkRequestData
{
    [JsonPropertyName("query")]
    public string Query { get; set; }

    [JsonPropertyName("threshold")]
    public decimal Threshold { get; set; }

    [JsonPropertyName("aggregateByDocument")]
    public bool AggregateByDocument { get; set; }

    [JsonPropertyName("max_results")]
    public int MaxResults { get; set; }

}

public class DocumentResponseData
{
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("results")]
    public DocumentResponseItemData[] Results { get; set; }
}
public class DocumentResponseItemData
{
    [JsonPropertyName("id")]
    public string Id { get; set; }

    [JsonPropertyName("source")]
    public string Source { get; set; }

    [JsonPropertyName("document")]
    public string Document { get; set; }

    [JsonPropertyName("similarity")]
    public decimal Similarity { get; set; }
}

public class ChunkResponseData
{
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("results")]
    public ChunkResponseItemData[] Results { get; set; }
}
public class ChunkResponseItemData
{
    [JsonPropertyName("id")]
    public string Id { get; set; }

    [JsonPropertyName("source")]
    public string Source { get; set; }

    [JsonPropertyName("chunk")]
    public string Document { get; set; }

    [JsonPropertyName("metadata")]
    public ChunkMetadata Metadata { get; set; }

    [JsonPropertyName("similarity")]
    public decimal Similarity { get; set; }
}

public class ChunkMetadata
{
    [JsonPropertyName("line_range")]
    public string LineRange { get; set; }
}

public class ChunkAggregatedResponseData
{
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("results")]
    public ChunkAggregatedResponseItemData[] Results { get; set; }
}

public class ChunkAggregatedResponseItemData
{
    [JsonPropertyName("source")]
    public string Source { get; set; }

    [JsonPropertyName("chunks")]
    public ChunkResponseItemData[] Chunks { get; set; }

}


internal static class HttpClientExt
{
    public static async Task<DocumentResponseData> ReadJsonDocumentsAsync(this HttpClient client, RequestData request, string requestUri, CancellationToken cancellationToken)
    {
        string jsonPayload = JsonSerializer.Serialize(request);
        using var response = await client.PostAsync(requestUri, new StringContent(jsonPayload, System.Text.Encoding.UTF8, "application/json"));
        if (response.StatusCode != System.Net.HttpStatusCode.OK)
        {
            throw new HttpRequestException($"Request failed with status code {response.StatusCode}");
        }
        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        var result = JsonSerializer.Deserialize<DocumentResponseData>(content);
        return result;
    }

    public static async Task<ChunkResponseData> ReadJsonChunksAsync(this HttpClient client, ChunkRequestData request, string requestUri, CancellationToken cancellationToken)
    {
        if (request.AggregateByDocument == true)
        {
            throw new Exception("AggregateByDocument must be false to use this endpoint. Use ReadJsonChunksAggregatedAsync instead.");
        }
        string jsonPayload = JsonSerializer.Serialize(request);
        using var response = await client.PostAsync(requestUri, new StringContent(jsonPayload, System.Text.Encoding.UTF8, "application/json"));
        if (response.StatusCode != System.Net.HttpStatusCode.OK)
        {
            throw new HttpRequestException($"Request failed with status code {response.StatusCode}");
        }
        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        var result = JsonSerializer.Deserialize<ChunkResponseData>(content);
        return result;
    }

    public static async Task<ChunkAggregatedResponseData> ReadJsonChunksAggregatedAsync(this HttpClient client, ChunkRequestData request, string requestUri, CancellationToken cancellationToken)
    {
        if (request.AggregateByDocument == false)
        {
            throw new Exception("AggregateByDocument must be true to use this endpoint. Use ReadJsonChunksAsync instead.");
        }
        string jsonPayload = JsonSerializer.Serialize(request);
        using var response = await client.PostAsync(requestUri, new StringContent(jsonPayload, System.Text.Encoding.UTF8, "application/json"));
        if (response.StatusCode != System.Net.HttpStatusCode.OK)
        {
            throw new HttpRequestException($"Request failed with status code {response.StatusCode}");
        }
        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        var result = JsonSerializer.Deserialize<ChunkAggregatedResponseData>(content);
        return result;
    }
}

[McpServerToolType]
public static class MCPs
{
    [McpServerTool(Name = "localDocumentsSearch"), Description("Finds the best local documents")]
    public static string LocalDocumentsSearch(string prompt, HttpClient client, CancellationToken cancellationToken, [Description("Threashold of similarity of documents to return")] decimal threshold = 0.6m, int maxResults = 5, bool returnDocument = true)
    {   
        DocumentResponseData response = GetBestLocalDocument(prompt, client, threshold, maxResults, returnDocument, cancellationToken);

        return JsonSerializer.Serialize(response);
    }


    [McpServerTool(Name = "localChunksSearch"), Description("Finds the best local chunks")]
    public static string LocalChunksSearch(string prompt, HttpClient client, CancellationToken cancellationToken, [Description("Threashold of similarity of chunks to return")] decimal threshold = 0.6m, int maxResults = 5, bool aggregateByDocument = false)
    {
        object response = GetBestLocalChunks(prompt, client, threshold, maxResults, aggregateByDocument, cancellationToken);

        var json = JsonSerializer.Serialize(response);
        return json;
    }

    private static DocumentResponseData GetBestLocalDocument(string prompt, HttpClient client, decimal threashold, int maxResults, bool returnDocument, CancellationToken cancellationToken)
    {
        var requestData = new RequestData
        {
            Query = prompt,
            Threshold = threashold,
            MaxResults = maxResults,
            ReturContent = returnDocument
        };
        var urlItem = Environment.GetEnvironmentVariable("Ollama-RAG-Sync-ProxyUrl");

        string url = "http://localhost:10001/api/search/documents";
        if (urlItem != null)
        {
            url = urlItem;
        }
        var docTasks = client.ReadJsonDocumentsAsync(requestData, url, cancellationToken);
        var response = docTasks.Result;


        return response;
    }

    private static object GetBestLocalChunks(string prompt, HttpClient client, decimal threashold, int maxResults, bool aggregateByDocument, CancellationToken cancellationToken)
    {
        var requestData = new ChunkRequestData
        {
            Query = prompt,
            Threshold = threashold,
            AggregateByDocument = aggregateByDocument,
            MaxResults = maxResults
        };
        var urlItem = Environment.GetEnvironmentVariable("Ollama-RAG-Sync-ProxyUrl");

        string url = "http://localhost:10001/api/search/chunks";
        if (urlItem != null)
        {
            url = urlItem;
        }

        if (requestData.AggregateByDocument)
        {
            var task = client.ReadJsonChunksAggregatedAsync(requestData, url, cancellationToken);
            var response = task.Result;
            return response;
        }
        else
        {
            var task = client.ReadJsonChunksAsync(requestData, url, cancellationToken);
            var response = task.Result;
            return response;
        }
    }
}
