using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.Links
{
    public class LinkSearchM
    {
        public UnitLookupVm Source { get; set; }
        public string Name { get; set; }
        public StatUnitTypes? Type { get; set; }
    }

    internal class LinkSearchMValidator : AbstractValidator<LinkSearchM>
    {
        public LinkSearchMValidator()
        {
            RuleFor(v => v.Source)
                .NotNull()
                .When(v => string.IsNullOrEmpty(v.Name))
                .WithMessage("Name and Source empty"); //TODO: LOCALIZE
            RuleFor(v => v.Name)
                .NotEmpty()
                .When(v => v.Source == null)
                .WithMessage("Name and Source empty"); //TODO: LOCALIZE
        }
    }
}
