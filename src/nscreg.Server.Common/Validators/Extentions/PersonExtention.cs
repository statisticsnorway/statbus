using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Validators.Extentions
{
    public static class PersonExtention
    {
        public static Person UpdateProperties(this Person person, PersonM model)
        {
            person.Address = model.Address;
            person.BirthDate = model.BirthDate;
            person.CountryId = model.CountryId;
            person.GivenName = model.GivenName;
            person.PersonalId = model.PersonalId;
            person.PhoneNumber = model.PhoneNumber;
            person.PhoneNumber1 = model.PhoneNumber1;
            person.Role = model.Role;
            person.Sex = model.Sex;
            person.Surname = model.Surname;

            return person;
        }
    }
}
