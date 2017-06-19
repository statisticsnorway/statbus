using System;
using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.Models.StatUnits
{
    public class PersonM
    {
        [NotCompare]
        public int? Id { get; set; }
        public string GivenName { get; set; }
        public string PersonalId { get; set; } // National personal ID of person (if it exists)(In Kyrgyzstan it calls ИНН)
        public string Surname { get; set; }
        public DateTime? BirthDate { get; set; }
        public byte Sex { get; set; }
        public PersonTypes Role { get; set; }
        public int CountryId { get; set; }
        public string PhoneNumber { get; set; }
        public string PhoneNumber1 { get; set; }
        public string Address { get; set; }

    }

    public class PersonMValidator : AbstractValidator<PersonM>
    {
        public PersonMValidator()
        {
            RuleFor(v => v.GivenName)
                .NotEmpty();
            RuleFor(v => v.Surname)
                .NotEmpty();
            RuleFor(v => v.CountryId)
                .GreaterThan(0);
        }
    }
}
