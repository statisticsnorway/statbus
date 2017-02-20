using System;
using FluentValidation.Validators;

namespace nscreg.Server.Validators
{
    public class CheckIntGreaterThan0OrGreaterThanValueValidator : PropertyValidator
    {
        private int compareTo;
        public CheckIntGreaterThan0OrGreaterThanValueValidator(int compareTo = 0) : base(string.Empty)
        {
            this.compareTo = compareTo;
        }
        protected override bool IsValid(PropertyValidatorContext context)
        {
            var value = Convert.ToInt32(context.PropertyValue);

            if (compareTo > 0)
                return value > 0 && value <= compareTo;

            return value > 0;
        }

    }
}
