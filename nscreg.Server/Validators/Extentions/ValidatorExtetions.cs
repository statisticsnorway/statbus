using FluentValidation;
using nscreg.Resources.Languages;
using Newtonsoft.Json;

namespace nscreg.Server.Validators.Extentions
{
    public static class ValidatorExtensions
    {
        public static IRuleBuilderOptions<T, int> CheckIntGreaterThan0OrLessThanValueValidator<T>(this IRuleBuilder<T, int> ruleBuilder, int compareTo = 0)
        {
            if (compareTo <= 0)
                return ruleBuilder.SetValidator(new CheckIntGreaterThan0OrGreaterThanValueValidator()).WithMessage(nameof(Resource.IncorrectIntegerValue));

            return ruleBuilder.SetValidator(new CheckIntGreaterThan0OrGreaterThanValueValidator(compareTo))
                .WithMessage(JsonConvert.SerializeObject(
                    new
                    {
                        LocalizedKey = nameof(Resource.IncorrectIntegerValueExt),
                        Parameters = new[] {compareTo}
                    })
                );
        }

        public static IRuleBuilderOptions<T, string> CheckStringNotEmptyAndGreaterThanValidator<T>(this IRuleBuilder<T, string> ruleBuilder, int maxLength)
        {
            return ruleBuilder.SetValidator(new CheckStringNotEmptyAndGreaterThanValidator(maxLength))
                .WithMessage(JsonConvert.SerializeObject(
                    new
                    {
                        LocalizedKey = nameof(Resource.IncorrectStringValue),
                        Parameters = new[] { maxLength }
                    })
                );
        }
    }
}
