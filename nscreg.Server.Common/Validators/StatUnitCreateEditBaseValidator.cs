using FluentValidation;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Validators
{
    public class StatUnitModelBaseValidator<T> : AbstractValidator<T> where T : StatUnitModelBase
    {
        //TODO: when we will know validation fields, we will use this validator for write base rules for create and edit StatUnit
        protected StatUnitModelBaseValidator()
        {
            RuleForEach(v => v.Activities)
                .SetValidator(new ActivityMValidator());

            RuleFor(v => v.ChangeReason)
                .Must(v =>
                    v == ChangeReasons.Create ||
                    v == ChangeReasons.Edit ||
                    v == ChangeReasons.Correction)
                .WithMessage(nameof(Resource.ChangeReasonMandatory));

            RuleFor(v => v.EditComment)
                .NotEmpty()
                .When(v => v.ChangeReason == ChangeReasons.Edit)
                .WithMessage(nameof(Resource.EditCommentMandatory));

            RuleFor(x => x.Name)
                .NotEmpty()
                .WithMessage(nameof(Resource.NameIsRequired));

            RuleFor(x => x.EmailAddress)
                .EmailAddress();
        }
    }
}
