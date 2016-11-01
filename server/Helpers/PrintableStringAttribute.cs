using System.ComponentModel.DataAnnotations;

namespace Server.Helpers
{
    public class PrintableStringAttribute : ValidationAttribute
    {
        protected override ValidationResult IsValid(object value, ValidationContext validationContext)
            => ((string)value).IsPrintable()
                ? ValidationResult.Success
                : new ValidationResult("String contains invalid characters");
    }
}
