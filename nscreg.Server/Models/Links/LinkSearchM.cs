using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.Links
{
    public class LinkSearchM
    {
        public UnitLookupVm Source { get; set; }
        public string Name { get; set; }
        public StatUnitTypes? Type { get; set; }
        public decimal? TurnoverFrom { get; set; }
        public decimal? TurnoverTo { get; set; }
        public string GeographicalCode { get; set; }
        public int? EmployeesFrom { get; set; }
        public int? EmployeesTo { get; set; }
        public string DataSource { get; set; }
    }

    internal class LinkSearchMValidator : AbstractValidator<LinkSearchM>
    {
        public LinkSearchMValidator()
        {
            RuleFor(v => v.Source)
                .NotNull()
                .When(v => string.IsNullOrEmpty(v.Name))
                .WithMessage(Resource.LinksNameOrStatIdRequred);
            RuleFor(v => v.Name)
                .NotEmpty()
                .When(v => v.Source == null)
                .WithMessage(Resource.LinksNameOrStatIdRequred);
        }
    }
}
