using FluentValidation.Validators;

namespace nscreg.Server.Validators
{
    public class CheckStringNotEmptyAndGreaterThanValidator : PropertyValidator
    {
        private readonly int _maxLength;

        public CheckStringNotEmptyAndGreaterThanValidator(int maxLength) : base(string.Empty)
        {
            _maxLength = maxLength;
        }

        protected override bool IsValid(PropertyValidatorContext context)
        {
            var value = context.PropertyValue as string;
            return value != null && value.Length <= _maxLength;
        }
    }
}
