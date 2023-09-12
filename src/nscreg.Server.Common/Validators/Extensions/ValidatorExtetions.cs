using System;
using FluentValidation;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Validators.Extensions
{
    /// <summary>
    /// Validation extension class
    /// </summary>
    public static class ValidatorExtensions
    {
        /// <summary>
        /// Method validator of the year
        /// </summary>
        /// <param name = "ruleBuilder"> Rule constructor </param>
        /// <param name = "minYear"> The least year to start </param>
        /// <returns> </returns>
        public static IRuleBuilderOptions<T, int> Year<T>(this IRuleBuilder<T, int> ruleBuilder, int minYear = 1900)
            => ruleBuilder
                .GreaterThan(minYear)
                .Must(v => v <= DateTime.Today.Year);

        /// <summary>
        /// Message format validator method
        /// </summary>
        /// <param name = "ruleBuilder"> Rule constructor </param>
        /// <param name = "localizedKey"> Localization key </param>
        /// <param name = "parameters"> Parameter </param>
        /// <returns> </returns>
        public static IRuleBuilderOptions<TModel, TProperty> WithFormatMessage<TModel, TProperty>(
            this IRuleBuilderOptions<TModel, TProperty> ruleBuilder,
            string localizedKey,
            params object[] parameters)
            =>
                ruleBuilder.WithMessage(JsonConvert.SerializeObject(
                    new
                    {
                        LocalizedKey = localizedKey,
                        Parameters = parameters,
                    })
                );
    }
}
