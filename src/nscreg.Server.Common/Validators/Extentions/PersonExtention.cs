using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Validators.Extentions
{
    /// <summary>
    /// Класс расширения персоны
    /// </summary>
    public static class PersonExtention
    {
        /// <summary>
        /// Метод обновления свойств персоны
        /// </summary>
        /// <param name="person">объект персоны</param>
        /// <param name="model">Модель персоны</param>
        /// <returns></returns>
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
            person.MiddleName = model.MiddleName;

            return person;
        }
    }
}
