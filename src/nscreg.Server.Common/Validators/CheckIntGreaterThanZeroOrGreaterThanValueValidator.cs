using System;
using FluentValidation.Validators;

namespace nscreg.Server.Common.Validators
{
    /// <summary>
    /// Класс валидатор строки на не пустые и больше значения
    /// </summary>
    public class CheckIntGreaterThanZeroOrGreaterThanValueValidator : PropertyValidator
    {
        private readonly int _compareTo;

        public CheckIntGreaterThanZeroOrGreaterThanValueValidator(int compareTo = 0) : base(string.Empty)
        {
            _compareTo = compareTo;
        }

        /// <summary>
        /// Метод проверки на валидность числа
        /// </summary>
        /// <param name="context">Контекст валидатора свойств</param>
        /// <returns></returns>
        protected override bool IsValid(PropertyValidatorContext context)
        {
            var value = Convert.ToInt32(context.PropertyValue);
            return _compareTo > 0
                ? value > 0 && value <= _compareTo
                : value > 0;
        }
    }
}
