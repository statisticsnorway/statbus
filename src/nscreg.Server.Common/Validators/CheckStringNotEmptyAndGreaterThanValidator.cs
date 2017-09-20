using FluentValidation.Validators;

namespace nscreg.Server.Common.Validators
{
    /// <summary>
    /// Класс валидатор строки на не пустые и больше значения
    /// </summary>
    public class CheckStringNotEmptyAndGreaterThanValidator : PropertyValidator
    {
        private readonly int _maxLength;

        public CheckStringNotEmptyAndGreaterThanValidator(int maxLength) : base(string.Empty)
        {
            _maxLength = maxLength;
        }

        /// <summary>
        /// Метод проверки на валидность числа
        /// </summary>
        /// <param name="context">Контекст валидатора свойств</param>
        /// <returns></returns>
        protected override bool IsValid(PropertyValidatorContext context)
        {
            var value = context.PropertyValue as string;
            return value != null && value.Length <= _maxLength;
        }
    }
}
