using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Server;
using ORSMcp.Services;

namespace ORSMcp
{
    /// <summary>
    /// Main entry point for the Ollama RAG Sync MCP server application.
    /// This server provides Model Context Protocol tools for searching local document collections
    /// using semantic similarity via vector embeddings.
    /// </summary>
    public class Program
    {
        /// <summary>
        /// The main entry point for the application.
        /// </summary>
        /// <param name="args">Command-line arguments.</param>
        /// <returns>A task that represents the asynchronous operation.</returns>
        static async Task Main(string[] args)
        {
            var builder = Host.CreateApplicationBuilder(args);
            
            // Configure logging to use stderr for MCP protocol compliance
            builder.Logging.AddConsole(consoleLogOptions =>
            {
                consoleLogOptions.LogToStandardErrorThreshold = LogLevel.Trace;
            });

            // Configure MCP server with stdio transport and register tools
            builder.Services
                .AddMcpServer()
                .WithStdioServerTransport()
                .WithToolsFromAssembly();

            // Register services
            builder.Services.AddSingleton<HttpClient>(sp =>
            {
                var logger = sp.GetRequiredService<ILogger<Program>>();
                logger.LogInformation("Initializing HttpClient for RAG operations");
                
                var client = new HttpClient
                {
                    Timeout = TimeSpan.FromSeconds(30)
                };
                
                return client;
            });

            builder.Services.AddSingleton<ISearchService, SearchService>();

            // Build and run the host
            var host = builder.Build();
            
            var logger = host.Services.GetRequiredService<ILogger<Program>>();
            logger.LogInformation("Ollama RAG Sync MCP Server starting...");
            
            try
            {
                await host.RunAsync();
            }
            catch (Exception ex)
            {
                logger.LogCritical(ex, "Application terminated unexpectedly");
                throw;
            }
        }
    }
}
