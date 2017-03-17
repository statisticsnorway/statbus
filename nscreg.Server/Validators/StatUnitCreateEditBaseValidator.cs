using FluentValidation;
using nscreg.Server.Models.StatUnits;

namespace nscreg.Server.Validators
{
    public class StatUnitModelBaseValidator<T>:AbstractValidator<T> where T: StatUnitModelBase
    {
        //TODO: when we will know validation fields, we will use this validator for write base rules for create and edit StatUnit
        protected StatUnitModelBaseValidator()
        {
        }
    }
}
