using System;
using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Models.DataSources
{
    /// <summary>
    /// Search Query Model
    /// </summary>
    public class SearchQueryM
    {
        public string Wildcard { get; set; }
        public int StatUnitType { get; set; } = 0;
        public string Restriction { get; set; }
        public int Priority { get; set; } = 0;
        public int AllowedOperations { get; set; } = 0;
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;
        public string SortBy { get; set; }
        public OrderRule OrderByValue { get; private set; } = OrderRule.Desc;
        public string OrderBy
        {
            set
            {
                if (Enum.TryParse(value, out OrderRule parsed))
                    OrderByValue = parsed;
            }
        }
        public bool GetAll { get; set; } = false;
    }

    /// <summary>
    /// Search Query Validation Model
    /// </summary>
    // ReSharper disable once ArrangeTypeModifiers
    class SearchQueryMValidator : AbstractValidator<SearchQueryM>
    {
        public SearchQueryMValidator()
        {
            RuleFor(x => x.StatUnitType)
                .Must(x => x == 0 || Enum.IsDefined(typeof(StatUnitTypes), x))
                .WithMessage(nameof(Resource.BadDataSourceRestrictionSearch));

            RuleFor(x => x.Priority)
                .Must(x => x == 0 || Enum.IsDefined(typeof(DataSourcePriority), x))
                .WithMessage(nameof(Resource.BadDataSourcePrioritySearch));

            RuleFor(x => x.AllowedOperations)
                .Must(x => x == 0 || Enum.IsDefined(typeof(DataSourceAllowedOperation), x))
                .WithMessage(nameof(Resource.BadDataSourceAllowedOperationsSearch));

            RuleFor(x => x.Page)
                .GreaterThanOrEqualTo(0)
                .WithMessage(nameof(Resource.PageError));

            RuleFor(x => x.PageSize)
                .GreaterThan(0)
                .WithMessage(nameof(Resource.PageSizeError));
        }
    }
}
