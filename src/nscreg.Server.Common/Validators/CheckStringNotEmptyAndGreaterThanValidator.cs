using FluentValidation.Validators;

namespace nscreg.Server.Common.Validators
{
    /// <summary>
    /// String validator class on non-empty and larger values
    /// </summary>
    public class CheckStringNotEmptyAndGreaterThanValidator : PropertyValidator
    {
        private readonly int _maxLength;

        public CheckStringNotEmptyAndGreaterThanValidator(int maxLength) : base(string.Empty)
        {
            _maxLength = maxLength;
        }

        /// <summary>
        /// Method for checking the validity of a number
        /// </summary>
        /// <param name = "context"> Context of the property validator </param>
        /// <returns> </returns>
        protected override bool IsValid(PropertyValidatorContext context)
        {
            var value = context.PropertyValue as string;
            return value != null && value.Length <= _maxLength;
        }
    }
}
