using FluentValidation;
using nscreg.Resources.Languages;

namespace nscreg.Server.Models.StatUnits
{
    public class SearchDeletedQueryM
    {
        public int Page { get; set;  }
        public int PageSize { get; set; }
    }

    public class SearchDeleteQueryMValidator : AbstractValidator<SearchDeletedQueryM>
    {
        public SearchDeleteQueryMValidator()
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
