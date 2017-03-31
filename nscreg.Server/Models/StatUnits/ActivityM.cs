using System;
using System.ComponentModel.DataAnnotations;
using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Validators.Extentions;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.Models.StatUnits
{
    public class ActivityM
    {
        [NotCompare]
        public int? Id { get; set; }
        [Required]
        [DataType(DataType.Date)]
        public DateTime? IdDate { get; set; }
        public int ActivityRevy { get; set; }
        public int ActivityYear { get; set; }
        public ActivityTypes ActivityType { get; set; }
        public int Employees { get; set; }
        public decimal Turnover { get; set; }
        [Required]
        public CodeLookupVm ActivityRevxCategory { get; set; }
    }

    public class ActivityMValidator : AbstractValidator<ActivityM>
    {
        public ActivityMValidator()
        {
            RuleFor(v => v.ActivityYear)
                .Year();
            RuleFor(v => v.Turnover)
                .GreaterThanOrEqualTo(0);
            RuleFor(v => v.Employees)
                .GreaterThanOrEqualTo(0);
        }
    }
}
