using System;
using FluentValidation;
using FluentValidation.Validators;

namespace nscreg.Server.Common.Validators
{
    /// <summary>
    /// String validator class on non-empty and larger values
    /// </summary>
    public class CheckStringNotEmptyAndGreaterThanValidator<T,TProperty> : PropertyValidator<T,TProperty>
    {
        private readonly int _maxLength;
        public override string Name => "CheckStringNotEmptyAndGreaterThanValidator";

        public CheckStringNotEmptyAndGreaterThanValidator(int maxLength) //: base(string.Empty)
        {
            _maxLength = maxLength;
        }

        /// <summary>
        /// Method for checking the validity of a number
        /// </summary>
        /// <param name = "context"> Context of the property validator </param>
        /// <returns> </returns>
        public override bool IsValid(ValidationContext<T> context, TProperty value)
        {
            if (value is string str)
            {
                return str.Length <= _maxLength;
            }
            return false;
        }

    }
}
