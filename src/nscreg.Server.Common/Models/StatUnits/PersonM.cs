using System;
using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Resources.Languages;

namespace nscreg.Server.Common.Models.StatUnits
{
    public class PersonM
    {
        [NotCompare]
        public int? Id { get; set; }
        public string GivenName { get; set; }
        public string PersonalId { get; set; } // National personal ID of person (if it exists)(In Kyrgyzstan it calls ИНН)
        public string Surname { get; set; }
        public string MiddleName { get; set; }
        public DateTimeOffset? BirthDate { get; set; }
        public byte? Sex { get; set; }
        public int? Role { get; set; }
        public int? CountryId { get; set; }
        public string PhoneNumber { get; set; }
        public string PhoneNumber1 { get; set; }
        public string Address { get; set; }
    }

    public class PersonMValidator : AbstractValidator<PersonM>
    {
        public PersonMValidator()
        {
            //RuleFor(v => v.GivenName)
            //    .NotEmpty().WithMessage(nameof(Resource.PersonsGivenNameRequired));
            //RuleFor(v => v.Surname)
            //    .NotEmpty().WithMessage(nameof(Resource.PersonsSurnameRequired)); ;
            //RuleFor(v => v.CountryId)
            //    .GreaterThan(0).WithMessage(nameof(Resource.PersonsCountryIdRequired)); ;
            //RuleFor(v => v.Role)
            //    .NotNull().WithMessage(nameof(Resource.PersonsRoleRequired));
        }
    }
}
