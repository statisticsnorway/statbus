using System.ComponentModel.DataAnnotations;
using nscreg.Utilities.Extensions;

namespace nscreg.Utilities.Attributes
{
    /// <summary>
    /// Класс атрибут печати строки
    /// </summary>
    public class PrintableStringAttribute : ValidationAttribute
    {
        /// <summary>
        /// Метод валидации результата
        /// </summary>
        /// <param name="value">Значение</param>
        /// <param name="validationContext">Контекст валидации</param>
        /// <returns></returns>
        protected override ValidationResult IsValid(object value, ValidationContext validationContext)
            => ((string)value).IsPrintable()
                ? ValidationResult.Success
                : new ValidationResult("String contains invalid characters");
    }
}
