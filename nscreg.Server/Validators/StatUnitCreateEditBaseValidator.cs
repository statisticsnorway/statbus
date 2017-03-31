using System.Collections.Generic;
using System.Linq;
using FluentValidation;
using Microsoft.EntityFrameworkCore.Internal;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Server.Models.StatUnits;

namespace nscreg.Server.Validators
{
    public class StatUnitModelBaseValidator<T>:AbstractValidator<T> where T: StatUnitModelBase
    {
        //TODO: when we will know validation fields, we will use this validator for write base rules for create and edit StatUnit
        protected StatUnitModelBaseValidator()
        {
            RuleFor(v => v.Activities)
                .NotEmpty()
                .WithMessage(nameof(Resource.StatUnitActivityErrorMustContainsPrimary))
                .Must(v =>
                {
                    if (v == null || v.Count == 0) return true;
                    return v.Any(x => x.ActivityType == ActivityTypes.Primary);
                })
                .WithMessage(nameof(Resource.StatUnitActivityErrorMustContainsPrimary));

            RuleForEach(v => v.Activities)
                .SetValidator(new ActivityMValidator());
        }
    }
}
