using System;
using FluentValidation.Validators;

namespace nscreg.Server.Common.Validators
{
    /// <summary>
    /// String validator class on non-empty and larger values
    /// </summary>
    public class CheckIntGreaterThanZeroOrGreaterThanValueValidator : PropertyValidator
    {
        private readonly int _compareTo;

        public CheckIntGreaterThanZeroOrGreaterThanValueValidator(int compareTo = 0) : base(string.Empty)
        {
            _compareTo = compareTo;
        }

        /// <summary>
        /// Method for checking the validity of a number
        /// </summary>
        /// <param name = "context"> Context of the property validator </param>
        /// <returns> </returns>
        protected override bool IsValid(PropertyValidatorContext context)
        {
            var value = Convert.ToInt32(context.PropertyValue);
            return _compareTo > 0
                ? value > 0 && value <= _compareTo
                : value > 0;
        }
    }
}
