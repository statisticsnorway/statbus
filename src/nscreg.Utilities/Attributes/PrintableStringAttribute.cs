using System.ComponentModel.DataAnnotations;
using nscreg.Utilities.Extensions;

namespace nscreg.Utilities.Attributes
{
    /// <summary>
    /// Class attribute print string
    /// </summary>
    public class PrintableStringAttribute : ValidationAttribute
    {
        /// <summary>
        /// Method for validating the result
        /// </summary>
        /// <param name = "value"> Value </param>
        /// <param name = "validationContext"> Validation context </param>
        /// <returns> </returns>
        protected override ValidationResult IsValid(object value, ValidationContext validationContext)
            => ((string)value).IsPrintable()
                ? ValidationResult.Success
                : new ValidationResult("String contains invalid characters");
    }
}
