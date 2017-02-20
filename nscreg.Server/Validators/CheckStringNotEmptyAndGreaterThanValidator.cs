using FluentValidation.Validators;

namespace nscreg.Server.Validators
{
    public class CheckStringNotEmptyAndGreaterThanValidator:PropertyValidator
    {
        private int maxLength;
        public CheckStringNotEmptyAndGreaterThanValidator(int maxLength) : base(string.Empty)
        {
            this.maxLength = maxLength;
        }

        protected override bool IsValid(PropertyValidatorContext context)
        {
            var value = context.PropertyValue as string;

            return value != null && value.Length <= maxLength;
        }
    }
}
