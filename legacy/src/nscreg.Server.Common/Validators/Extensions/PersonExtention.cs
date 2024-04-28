using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Validators.Extensions
{
    /// <summary>
    /// Person extension class
    /// </summary>
    public static class PersonExtention
    {
        /// <summary>
        /// Person property update method
        /// </summary>
        /// <param name = "person"> person object </param>
        /// <param name = "model"> Person model </param>
        /// <returns> </returns>
        public static Person UpdateProperties(this Person person, PersonM model)
        {
            person.Address = model.Address;
            person.BirthDate = model.BirthDate;
            person.CountryId = model.CountryId;
            person.GivenName = model.GivenName;
            person.PersonalId = model.PersonalId;
            person.PhoneNumber = model.PhoneNumber;
            person.PhoneNumber1 = model.PhoneNumber1;
            person.Sex = model.Sex;
            person.Surname = model.Surname;
            person.MiddleName = model.MiddleName;

            return person;
        }
    }
}
