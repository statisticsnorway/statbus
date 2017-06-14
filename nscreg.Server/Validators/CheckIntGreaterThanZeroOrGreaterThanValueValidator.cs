using System;
using FluentValidation.Validators;

namespace nscreg.Server.Validators
{
    public class CheckIntGreaterThanZeroOrGreaterThanValueValidator : PropertyValidator
    {
        private readonly int _compareTo;

        public CheckIntGreaterThanZeroOrGreaterThanValueValidator(int compareTo = 0) : base(string.Empty)
        {
            _compareTo = compareTo;
        }

        protected override bool IsValid(PropertyValidatorContext context)
        {
            var value = Convert.ToInt32(context.PropertyValue);
            return _compareTo > 0
                ? value > 0 && value <= _compareTo
                : value > 0;
        }
    }
}
