using FluentValidation;
using FluentValidation.Results;
using System.Collections.Generic;

namespace nscreg.Server.Models
{
    public interface ISubmitModel
    {
        IEnumerable<ValidationResult> Validate(ValidationContext validationContext);
    }
}
