using System;
using FluentValidation;
using nscreg.Resources.Languages;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Validators.Extentions
{
    /// <summary>
    /// Класс расширения валидации
    /// </summary>
    public static class ValidatorExtensions
    {
        /// <summary>
        /// Метод валидатор числа больше чем 0 или меньше значение
        /// </summary>
        /// <param name="ruleBuilder">Конструктор правил</param>
        /// <param name="compareTo">Сравнение с</param>
        /// <returns></returns>
        public static IRuleBuilderOptions<T, int> CheckIntGreaterThan0OrLessThanValueValidator<T>(
            this IRuleBuilder<T, int> ruleBuilder,
            int compareTo = 0)
            =>
                compareTo <= 0
                    ? ruleBuilder.SetValidator(new CheckIntGreaterThanZeroOrGreaterThanValueValidator())
                        .WithMessage(nameof(Resource.IncorrectIntegerValue))
                    : ruleBuilder.SetValidator(new CheckIntGreaterThanZeroOrGreaterThanValueValidator(compareTo))
                        .WithMessage(
                            JsonConvert.SerializeObject(
                                new
                                {
                                    LocalizedKey = nameof(Resource.IncorrectIntegerValueExt),
                                    Parameters = new[] {compareTo}
                                }));

        /// <summary>
        /// Метод валидатор строки на не пустые и больше значения
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <param name="ruleBuilder"></param>
        /// <param name="maxLength"></param>
        /// <returns></returns>
        public static IRuleBuilderOptions<T, string> CheckStringNotEmptyAndGreaterThanValidator<T>(
            this IRuleBuilder<T, string> ruleBuilder,
            int maxLength)
            =>
                ruleBuilder.SetValidator(new CheckStringNotEmptyAndGreaterThanValidator(maxLength))
                    .WithMessage(JsonConvert.SerializeObject(
                        new
                        {
                            LocalizedKey = nameof(Resource.IncorrectStringValue),
                            Parameters = new[] {maxLength}
                        })
                    );

        /// <summary>
        /// Метод валидатор года
        /// </summary>
        /// <param name="ruleBuilder">Конструктор правил</param>
        /// <param name="minYear">Наименьший год начала</param>
        /// <returns></returns>
        public static IRuleBuilderOptions<T, int> Year<T>(this IRuleBuilder<T, int> ruleBuilder, int minYear = 1900)
            => ruleBuilder
                .GreaterThan(minYear)
                .Must(v => v <= DateTime.Today.Year);

        /// <summary>
        /// Метод валидатор формата сообщений
        /// </summary>
        /// <param name="ruleBuilder">Конструктор правил</param>
        /// <param name="localizedKey">Ключ локализации</param>
        /// <param name="parameters">Параметр</param>
        /// <returns></returns>
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
