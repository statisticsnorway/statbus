using FluentValidation;
using nscreg.Data.Constants;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;

namespace nscreg.Server.Models.StatUnits
{
    public class SearchQueryM : IValidatableObject
    {
        public string Wildcard { get; set; }
        public StatUnitTypes? Type { get; set; }
        public string TerritorialCode { get; set; }
        public bool IncludeLiquidated { get; set; } = false;
        public DateTime? LastChangeFrom { get; set; }
        public DateTime? LastChangeTo { get; set; }
        public int Page { get; set; } = 0;
        public int PageSize { get; set; } = 12;

        public IEnumerable<ValidationResult> Validate(System.ComponentModel.DataAnnotations.ValidationContext validationContext)
        {
            var validator = new Validator();
            var result = validator.Validate(this);
            return result.Errors.Select(x => new ValidationResult(x.ErrorMessage, new[] { x.PropertyName }));
        }

        private class Validator : AbstractValidator<SearchQueryM>
        {
            public Validator()
            {
                RuleFor(x => x.Page).GreaterThanOrEqualTo(0).WithMessage("page nubmer should not be negative");
                RuleFor(x => x.PageSize).GreaterThan(0).WithMessage("page size must be greater than 0");
            }
        }
    }
}
