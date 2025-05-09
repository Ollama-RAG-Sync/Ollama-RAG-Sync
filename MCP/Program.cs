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

    [JsonPropertyName("chunk")]
    public string Document { get; set; }

    [JsonPropertyName("similarity")]
    public decimal Similarity { get; set; }
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
    public static async Task<ChunkResponseData> ReadJsonChunksAsync(this HttpClient client, RequestData request, string requestUri, CancellationToken cancellationToken)
    {
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

}

[McpServerToolType]
public static class EchoTool
{
    [McpServerTool(Name = "localDocumentsSearch"), Description("Finds the best local documents and chunks")]
    public static string LocalDocumentsSearch(string prompt, HttpClient client, CancellationToken cancellationToken, [Description("Threashold of similarity of documents to return")] decimal threashold = 0.7m)
    {   
        Debugger.Launch();
        DocumentResponseData response = GetBestLocalDocument(prompt, client, threashold, cancellationToken);
        ChunkResponseData responseChunk = GetBestLocalChunk(prompt, client, threashold, cancellationToken);

        return JsonSerializer.Serialize(new { BestDocument = response, BestChunk = responseChunk.Results.FirstOrDefault() });
    }

    private static DocumentResponseData GetBestLocalDocument(string prompt, HttpClient client, decimal threashold, CancellationToken cancellationToken)
    {
        var requestData = new RequestData
        {
            Query = prompt,
            Threshold = threashold
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


    private static ChunkResponseData GetBestLocalChunk(string prompt, HttpClient client, decimal threashold, CancellationToken cancellationToken)
    {
        var requestData = new RequestData
        {
            Query = prompt,
            Threshold = threashold
        };
        var urlItem = Environment.GetEnvironmentVariable("Ollama-RAG-Sync-ProxyUrl");

        string url = "http://localhost:10001/api/search/chunks";
        if (urlItem != null)
        {
            url = urlItem;
        }
        var task = client.ReadJsonChunksAsync(requestData, url, cancellationToken);

        var response = task.Result;
        return response;
    }
}
