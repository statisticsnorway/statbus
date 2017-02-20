using FluentValidation;
using nscreg.Server.Models.StatUnits.Base;

namespace nscreg.Server.Validators
{
    public class StatUnitCreateEditBaseValidator<T>:AbstractValidator<T> where T: StatUnitCreateEditBaseM
    {
        //TODO: when we will know validation fields, we will use this validator for write base rules for create and edit StatUnit
        protected StatUnitCreateEditBaseValidator()
        {
        }
    }
}
