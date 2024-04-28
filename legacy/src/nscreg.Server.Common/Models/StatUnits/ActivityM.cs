using System;
using System.ComponentModel.DataAnnotations;
using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Resources.Languages;

namespace nscreg.Server.Common.Models.StatUnits
{
    public class ActivityM
    {
        [NotCompare]
        public int? Id { get; set; }
        [DataType(DataType.Date)]
        public DateTimeOffset? IdDate { get; set; }
        public int? ActivityYear { get; set; }
        public ActivityTypes ActivityType { get; set; }
        public int? Employees { get; set; }
        public decimal? Turnover { get; set; }
        [Required]
        public int ActivityCategoryId { get; set; }
    }

    public class ActivityMValidator : AbstractValidator<ActivityM>
    {
        public ActivityMValidator()
        {
            RuleFor(v => v.ActivityYear)
                .Must(x => x == 0 || (x >= 1900 && x <= DateTime.Now.Year - 1));
            RuleFor(v => v.Turnover)
                .GreaterThanOrEqualTo(0);
            RuleFor(v => v.Employees)
                .GreaterThanOrEqualTo(0);
            RuleFor(v => v.IdDate)
                .NotNull().WithMessage(nameof(Resource.ActivityIdDateRequired));
        }
    }
}
