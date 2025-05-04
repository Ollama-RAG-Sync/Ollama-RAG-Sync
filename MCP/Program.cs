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
public class ResponseData
{
    public bool Success { get; set; }

    [JsonPropertyName("results")]
    public ResponseItem[] Results { get; set; }
}
 public class ResponseItem
{
    [JsonPropertyName("id")]
    public string Id { get; set; }

    [JsonPropertyName("document")]
    public string Document { get; set; }

    [JsonPropertyName("similarity")]
    public decimal Similarity {get;set;}
}

internal static class HttpClientExt
{
    public static async Task<ResponseData> ReadJsonDocumentAsync(this HttpClient client, RequestData request, string requestUri, CancellationToken cancellationToken)
    {
        string jsonPayload = JsonSerializer.Serialize(request);
        using var response = await client.PostAsync(requestUri, new StringContent(jsonPayload, System.Text.Encoding.UTF8, "application/json"));
        if (response.StatusCode != System.Net.HttpStatusCode.OK)
        {
            throw new HttpRequestException($"Request failed with status code {response.StatusCode}");
        }
        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        var result = JsonSerializer.Deserialize<ResponseData>(content);
        return result;
    }
}

[McpServerToolType]
public static class EchoTool
{
    [McpServerTool(Name = "localDocumentsSearch"), Description("Finds the best local document")]
    public static string LocalDocumentsSearch(string prompt, HttpClient client, CancellationToken cancellationToken, [Description("Threashold of similarity of document to return")] decimal threashold = 0.7m)
    {
        Debugger.Launch();
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
        var task = client.ReadJsonDocumentAsync(requestData, url, cancellationToken);

        var response = task.Result;


        return JsonSerializer.Serialize(response);
    }
}
