using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Utilities.Enums;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Models.StatUnits
{
    public class StatUnitModelBase : IStatUnitM
    {
        public string StatId { get; set; }

        [DataType(DataType.Date)]
        public DateTime? StatIdDate { get; set; }

        public string TaxRegId { get; set; }

        [DataType(DataType.Date)]
        public DateTime? TaxRegDate { get; set; }

        public string ExternalId { get; set; }
        public string ExternalIdType { get; set; }

        [DataType(DataType.Date)]
        public DateTime? ExternalIdDate { get; set; }

        public string DataSource { get; set; }
        public string RefNo { get; set; }

        public string Name { get; set; }

        public int? ParentOrgLink { get; set; }
        public string ShortName { get; set; }
        public AddressM Address { get; set; }

        [DataType(DataType.PhoneNumber)]
        public string TelephoneNo { get; set; }

        [DataType(DataType.EmailAddress)]
        public string EmailAddress { get; set; }

        [DataType(DataType.Url)]
        public string WebAddress { get; set; }

        public int? RegMainActivityId { get; set; }
        public DateTime? RegistrationDate { get; set; }
        public int? RegistrationReasonId { get; set; }

        [DataType(DataType.Date)]
        public DateTime? LiqDate { get; set; }

        public string LiqReason { get; set; }
        public DateTime? SuspensionStart { get; set; }
        public DateTime? SuspensionEnd { get; set; }
        public string ReorgTypeCode { get; set; }

        [DataType(DataType.Date)]
        public DateTime? ReorgDate { get; set; }

        public int? ReorgReferences { get; set; }
        public AddressM ActualAddress { get; set; }
        public AddressM PostalAddress { get; set; }
        public string ContactPerson { get; set; }
        public int? Employees { get; set; }
        public int? NumOfPeopleEmp { get; set; }
        public int? EmployeesYear { get; set; }

        [DataType(DataType.Date)]
        public DateTime? EmployeesDate { get; set; }

        public decimal? Turnover { get; set; }

        public int? TurnoverYear { get; set; }

        [DataType(DataType.Date)]
        public DateTime? TurnoverDate { get; set; }

        [DataType(DataType.Date)]
        public DateTime? StatusDate { get; set; }

        public string Notes { get; set; }
        public bool FreeEconZone { get; set; }
        public bool Classified { get; set; }
        public List<ActivityM> Activities { get; set; }
        public List<PersonM> Persons { get; set; }
        public List<PersonStatUnitModel> PersonStatUnits { get; set; }
        public ChangeReasons ChangeReason { get; set; }
        public string EditComment { get; set; }
        public List<int> ForeignParticipationCountriesUnits { get; set; }
        public int? SizeId { get; set; }
        public int? ForeignParticipationId { get; set; }
        public int? DataSourceClassificationId { get; set; }
        public int? ReorgTypeId { get; set; }
        public int? UnitStatusId { get; set; }

        public IEnumerable<Permission> Permissions { get; set; }

        [JsonIgnore]
        public DataAccessPermissions DataAccess
        {
            get => Permissions != null ? new DataAccessPermissions(Permissions) : null;
            set => Permissions = value.Permissions;
        }
    }
}
