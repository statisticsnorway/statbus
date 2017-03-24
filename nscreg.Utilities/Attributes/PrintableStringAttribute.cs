using System.ComponentModel.DataAnnotations;
using nscreg.Utilities.Extensions;

namespace nscreg.Utilities
{
    public class PrintableStringAttribute : ValidationAttribute
    {
        protected override ValidationResult IsValid(object value, ValidationContext validationContext)
            => ((string)value).IsPrintable()
                ? ValidationResult.Success
                : new ValidationResult("String contains invalid characters");
    }
}
