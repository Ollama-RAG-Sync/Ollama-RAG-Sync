namespace ORSMcp.Exceptions
{
    /// <summary>
    /// Base exception for all RAG-related errors.
    /// </summary>
    public class RagException : Exception
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="RagException"/> class.
        /// </summary>
        public RagException()
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="RagException"/> class with a specified error message.
        /// </summary>
        /// <param name="message">The message that describes the error.</param>
        public RagException(string message) : base(message)
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="RagException"/> class with a specified error message
        /// and a reference to the inner exception that is the cause of this exception.
        /// </summary>
        /// <param name="message">The error message that explains the reason for the exception.</param>
        /// <param name="innerException">The exception that is the cause of the current exception.</param>
        public RagException(string message, Exception innerException) : base(message, innerException)
        {
        }
    }

    /// <summary>
    /// Exception thrown when a search operation fails.
    /// </summary>
    public class SearchException : RagException
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="SearchException"/> class.
        /// </summary>
        public SearchException()
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="SearchException"/> class with a specified error message.
        /// </summary>
        /// <param name="message">The message that describes the error.</param>
        public SearchException(string message) : base(message)
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="SearchException"/> class with a specified error message
        /// and a reference to the inner exception.
        /// </summary>
        /// <param name="message">The error message that explains the reason for the exception.</param>
        /// <param name="innerException">The exception that is the cause of the current exception.</param>
        public SearchException(string message, Exception innerException) : base(message, innerException)
        {
        }
    }

    /// <summary>
    /// Exception thrown when a required configuration value is missing or invalid.
    /// </summary>
    public class ConfigurationException : RagException
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="ConfigurationException"/> class.
        /// </summary>
        public ConfigurationException()
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="ConfigurationException"/> class with a specified error message.
        /// </summary>
        /// <param name="message">The message that describes the error.</param>
        public ConfigurationException(string message) : base(message)
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="ConfigurationException"/> class with a specified error message
        /// and a reference to the inner exception.
        /// </summary>
        /// <param name="message">The error message that explains the reason for the exception.</param>
        /// <param name="innerException">The exception that is the cause of the current exception.</param>
        public ConfigurationException(string message, Exception innerException) : base(message, innerException)
        {
        }
    }

    /// <summary>
    /// Exception thrown when the aggregation mode doesn't match the expected endpoint.
    /// </summary>
    public class InvalidAggregationModeException : RagException
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="InvalidAggregationModeException"/> class.
        /// </summary>
        /// <param name="expectedMode">The expected aggregation mode.</param>
        public InvalidAggregationModeException(bool expectedMode)
            : base($"AggregateByDocument must be {expectedMode} for this endpoint.")
        {
            ExpectedMode = expectedMode;
        }

        /// <summary>
        /// Gets the expected aggregation mode.
        /// </summary>
        public bool ExpectedMode { get; }
    }
}
