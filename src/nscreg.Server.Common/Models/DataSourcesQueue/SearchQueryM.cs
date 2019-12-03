using System;
using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
    /// <summary>
    /// Query Search Model
    /// </summary>
    public class SearchQueryM
    {
        public DateTime? DateFrom { get; set; }
        public DateTime? DateTo { get; set; }
        public DataSourceQueueStatuses? Status { get; set; }
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;
        public string SortBy { get; set; }
        public OrderRule OrderByValue { get; private set; } = OrderRule.Asc;
        public string OrderBy
        {
            set
            {
                OrderRule parsed;
                if (Enum.TryParse(value, out parsed))
                    OrderByValue = parsed;
            }
        }
    }

    /// <summary>
    /// Search Query Validation Model
    /// </summary>
    public class SearchQueryMValidator : AbstractValidator<SearchQueryM>
    {
        public SearchQueryMValidator()
        {
            RuleFor(x => x.Page)
                .GreaterThanOrEqualTo(0)
                .WithMessage(nameof(Resource.PageError));

            RuleFor(x => x.PageSize)
                .GreaterThan(0)
                .WithMessage(nameof(Resource.PageSizeError));
           
        }
    }
}
