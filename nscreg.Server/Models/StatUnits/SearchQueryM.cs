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
        public bool IncludeLiquidated { get; set; } = false;
        public decimal? EmployeesNumberFrom { get; set; }
        public decimal? EmployeesNumberTo { get; set; }
        public decimal? TurnoverFrom { get; set; }
        public decimal? TurnoverTo { get; set; }
        public string TerritorialCode { get; set; }
        public DateTime? LastChangeFrom { get; set; }
        public DateTime? LastChangeTo { get; set; }
        public int Page { get; set; } = 0;
        public int PageSize { get; set; } = 12;

        public IEnumerable<ValidationResult> Validate(System.ComponentModel.DataAnnotations.ValidationContext validationContext)
            => new Validator().Validate(this).Errors
            .Select(x => new ValidationResult(x.ErrorMessage, new[] { x.PropertyName }));

        private class Validator : AbstractValidator<SearchQueryM>
        {
            public Validator()
            {
                RuleFor(x => x.Page)
                    .GreaterThanOrEqualTo(0)
                    .WithMessage("PageNumNotNegative");

                RuleFor(x => x.PageSize)
                    .GreaterThan(0)
                    .WithMessage("page size must be greater than 0");

                RuleFor(x => x.LastChangeFrom)
                    .LessThanOrEqualTo(x => x.LastChangeTo)
                    .When(x => x.LastChangeFrom.HasValue && x.LastChangeTo.HasValue)
                    .WithMessage("last change from value is later than 'last change to'");

                RuleFor(x => x.LastChangeTo)
                    .GreaterThanOrEqualTo(x => x.LastChangeFrom)
                    .When(x => x.LastChangeFrom.HasValue && x.LastChangeTo.HasValue)
                    .WithMessage("last change to value is earlier than 'last change from'");

                RuleFor(x => x.EmployeesNumberFrom)
                    .GreaterThanOrEqualTo(0)
                    .When(x => x.EmployeesNumberFrom.HasValue)
                    .WithMessage("number of employees from shouldn't be negative");

                RuleFor(x => x.EmployeesNumberFrom)
                    .LessThanOrEqualTo(x => x.EmployeesNumberTo)
                    .When(x => x.EmployeesNumberFrom.HasValue && x.EmployeesNumberTo.HasValue)
                    .WithMessage("number of employees from is larger than 'number of employees to'");

                RuleFor(x => x.EmployeesNumberTo)
                    .GreaterThanOrEqualTo(0)
                    .When(x => x.EmployeesNumberTo.HasValue)
                    .WithMessage("number of employees to shouldn'be negative");

                RuleFor(x => x.EmployeesNumberTo)
                    .LessThanOrEqualTo(x => x.EmployeesNumberFrom)
                    .When(x => x.EmployeesNumberFrom.HasValue && x.EmployeesNumberTo.HasValue)
                    .WithMessage("number of employees to is less than 'number of employees from'");

                RuleFor(x => x.TurnoverFrom)
                    .GreaterThanOrEqualTo(0)
                    .When(x => x.TurnoverFrom.HasValue)
                    .WithMessage("turnover from shouldn't be negative");

                RuleFor(x => x.TurnoverFrom)
                    .LessThanOrEqualTo(x => x.TurnoverTo)
                    .When(x => x.TurnoverFrom.HasValue && x.TurnoverTo.HasValue)
                    .WithMessage("turnover from is larger than 'turnover to'");

                RuleFor(x => x.TurnoverTo)
                    .GreaterThanOrEqualTo(0)
                    .When(x => x.TurnoverTo.HasValue)
                    .WithMessage("turnover to shouldn'be negative");

                RuleFor(x => x.TurnoverTo)
                    .GreaterThanOrEqualTo(x => x.TurnoverFrom)
                    .When(x => x.TurnoverFrom.HasValue && x.TurnoverTo.HasValue)
                    .WithMessage("turnover to is less than 'turnover from'");
            }
        }
    }
}
