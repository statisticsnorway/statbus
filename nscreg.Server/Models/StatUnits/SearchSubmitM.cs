using FluentValidation;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;

namespace nscreg.Server.Models.StatUnits
{
    public class SearchSubmitM : IValidatableObject
    {
        public string Name { get; set; }

        public IEnumerable<ValidationResult> Validate(System.ComponentModel.DataAnnotations.ValidationContext validationContext)
        {
            var validator = new Validator();
            var result = validator.Validate(this);
            return result.Errors.Select(x => new ValidationResult(x.ErrorMessage, new[] { x.PropertyName }));
        }

        public class Validator : AbstractValidator<SearchSubmitM>
        {
            public Validator()
            {
                RuleFor(x => x.Name).NotEmpty().WithMessage("name is required");
            }
        }
    }
}
