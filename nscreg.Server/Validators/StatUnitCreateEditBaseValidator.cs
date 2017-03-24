using System.Collections.Generic;
using System.Linq;
using FluentValidation;
using Microsoft.EntityFrameworkCore.Internal;
using nscreg.Server.Models.StatUnits;

namespace nscreg.Server.Validators
{
    public class StatUnitModelBaseValidator<T>:AbstractValidator<T> where T: StatUnitModelBase
    {
        //TODO: when we will know validation fields, we will use this validator for write base rules for create and edit StatUnit
        protected StatUnitModelBaseValidator()
        {
            RuleFor(v => v.Activities)
                .Must(v =>
                {
                    if (v == null)
                    {
                        return true;
                    }
                    var set = new HashSet<int>();
                    return v.Where(item => item.Id.HasValue).All(item => set.Add(item.Id.Value));
                })
                .WithMessage("TODO: LOCALIZE Содержатся дубликаты");
        }
    }
}
