using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Person entity class
    /// </summary>
    public class Person : IModelWithId
    {
        public int Id { get; set; }

        [JsonIgnore]
        public DateTimeOffset IdDate { get; set; }
        [MaxLength(150)]
        public string GivenName { get; set; }

        // National personal ID of person (if it exists)(In Kyrgyzstan it calls ИНН)
        public string PersonalId { get; set; }
        [MaxLength(150)]
        public string Surname { get; set; }
        [MaxLength(150)]
        public string MiddleName { get; set; }
        public DateTimeOffset? BirthDate { get; set; }
        public byte? Sex { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? CountryId { get; set; }
        public virtual Country NationalityCode { get; set; }
        public string PhoneNumber { get; set; }
        public string PhoneNumber1 { get; set; }
        public string Address { get; set; }

        public int? Role { get; set; }
        [JsonIgnore]
        public virtual ICollection<PersonStatisticalUnit> PersonsUnits { get; set; }
    }
}
