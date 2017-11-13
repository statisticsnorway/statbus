using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность персоны
    /// </summary>
    public class Person
    {
        public int Id { get; set; }

        [JsonIgnore]
        public DateTime IdDate { get; set; }

        public string GivenName { get; set; }

        // National personal ID of person (if it exists)(In Kyrgyzstan it calls ИНН)
        public string PersonalId { get; set; }

        public string Surname { get; set; }
        public DateTime? BirthDate { get; set; }
        public byte Sex { get; set; }
        public PersonTypes Role { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int CountryId { get; set; }

        public virtual Country NationalityCode { get; set; }
        public string PhoneNumber { get; set; }
        public string PhoneNumber1 { get; set; }
        public string Address { get; set; }

        [JsonIgnore]
        public virtual ICollection<PersonStatisticalUnit> PersonsUnits { get; set; }
    }
}
