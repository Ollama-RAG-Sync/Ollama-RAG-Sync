using ORSMcp.Models;
using System.ComponentModel.DataAnnotations;

namespace ORSMcp.Tests.Models
{
    public class ModelValidationTests
    {
        private List<ValidationResult> ValidateModel<T>(T model)
        {
            var validationContext = new ValidationContext(model!);
            var validationResults = new List<ValidationResult>();
            Validator.TryValidateObject(model!, validationContext, validationResults, true);
            return validationResults;
        }

        [Fact]
        public void DocumentSearchRequest_ValidModel_ShouldPassValidation()
        {
            // Arrange
            var request = new DocumentSearchRequest
            {
                Query = "test query",
                CollectionName = "test-collection",
                Threshold = 0.7m,
                MaxResults = 10,
                ReturnContent = true
            };

            // Act
            var errors = ValidateModel(request);

            // Assert
            Assert.Empty(errors);
        }

        [Fact]
        public void DocumentSearchRequest_MissingQuery_ShouldFailValidation()
        {
            // Arrange
            var request = new DocumentSearchRequest
            {
                Query = "",
                CollectionName = "test-collection"
            };

            // Act
            var errors = ValidateModel(request);

            // Assert
            Assert.NotEmpty(errors);
            Assert.Contains(errors, e => e.MemberNames.Contains("Query"));
        }

        [Fact]
        public void DocumentSearchRequest_InvalidThreshold_ShouldFailValidation()
        {
            // Arrange
            var request = new DocumentSearchRequest
            {
                Query = "test",
                CollectionName = "test-collection",
                Threshold = 1.5m // Invalid: > 1.0
            };

            // Act
            var errors = ValidateModel(request);

            // Assert
            Assert.NotEmpty(errors);
            Assert.Contains(errors, e => e.MemberNames.Contains("Threshold"));
        }

        [Fact]
        public void ChunkSearchRequest_ValidModel_ShouldPassValidation()
        {
            // Arrange
            var request = new ChunkSearchRequest
            {
                Query = "test query",
                CollectionName = "test-collection",
                Threshold = 0.6m,
                MaxResults = 5,
                AggregateByDocument = false
            };

            // Act
            var errors = ValidateModel(request);

            // Assert
            Assert.Empty(errors);
        }

        [Fact]
        public void ChunkSearchRequest_InvalidMaxResults_ShouldFailValidation()
        {
            // Arrange
            var request = new ChunkSearchRequest
            {
                Query = "test",
                CollectionName = "test-collection",
                MaxResults = 0 // Invalid: < 1
            };

            // Act
            var errors = ValidateModel(request);

            // Assert
            Assert.NotEmpty(errors);
            Assert.Contains(errors, e => e.MemberNames.Contains("MaxResults"));
        }

        [Fact]
        public void DocumentSearchResponse_DefaultValues_ShouldBeValid()
        {
            // Arrange
            var response = new DocumentSearchResponse();

            // Assert
            Assert.False(response.Success);
            Assert.NotNull(response.Results);
            Assert.Empty(response.Results);
        }

        [Fact]
        public void ChunkSearchResponse_DefaultValues_ShouldBeValid()
        {
            // Arrange
            var response = new ChunkSearchResponse();

            // Assert
            Assert.False(response.Success);
            Assert.NotNull(response.Results);
            Assert.Empty(response.Results);
        }

        [Fact]
        public void ChunkAggregatedSearchResponse_DefaultValues_ShouldBeValid()
        {
            // Arrange
            var response = new ChunkAggregatedSearchResponse();

            // Assert
            Assert.False(response.Success);
            Assert.NotNull(response.Results);
            Assert.Empty(response.Results);
        }
    }
}
