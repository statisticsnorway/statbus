using System;
using FluentValidation;
using nscreg.Resources.Languages;
using Newtonsoft.Json;

namespace nscreg.Server.Validators.Extentions
{
    public static class ValidatorExtensions
    {
        public static IRuleBuilderOptions<T, int> CheckIntGreaterThan0OrLessThanValueValidator<T>(
            this IRuleBuilder<T, int> ruleBuilder,
            int compareTo = 0)
            => compareTo <= 0
                ? ruleBuilder
                    .SetValidator(new CheckIntGreaterThanZeroOrGreaterThanValueValidator())
                    .WithMessage(nameof(Resource.IncorrectIntegerValue))
                : ruleBuilder
                    .SetValidator(new CheckIntGreaterThanZeroOrGreaterThanValueValidator(compareTo))
                    .WithMessage(
                        JsonConvert.SerializeObject(
                            new
                            {
                                LocalizedKey = nameof(Resource.IncorrectIntegerValueExt),
                                Parameters = new[] {compareTo}
                            }));

        public static IRuleBuilderOptions<T, string> CheckStringNotEmptyAndGreaterThanValidator<T>(
            this IRuleBuilder<T, string> ruleBuilder,
            int maxLength)
            => ruleBuilder
                .SetValidator(new CheckStringNotEmptyAndGreaterThanValidator(maxLength))
                .WithMessage(
                    JsonConvert.SerializeObject(
                        new
                        {
                            LocalizedKey = nameof(Resource.IncorrectStringValue),
                            Parameters = new[] {maxLength}
                        }));

        public static IRuleBuilderOptions<T, int> Year<T>(
            this IRuleBuilder<T, int> ruleBuilder,
            int minYear = 1900)
            => ruleBuilder
                .GreaterThan(minYear)
                .Must(v => v <= DateTime.Today.Year);

        public static IRuleBuilderOptions<TModel, TProperty> WithFormatMessage<TModel, TProperty>(
            this IRuleBuilderOptions<TModel, TProperty> ruleBuilder,
            string localizedKey,
            params object[] parameters)
            =>
                ruleBuilder
                    .WithMessage(
                        JsonConvert.SerializeObject(
                            new
                            {
                                LocalizedKey = localizedKey,
                                Parameters = parameters,
                            }));
    }
}
