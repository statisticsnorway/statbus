using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Utilities.Enums;
using Newtonsoft.Json;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  The class is the essence of history units
    /// </summary>
    public abstract class StatisticalUnitHistory : IStatisticalUnitHistory
    {
        [Key]
        public int RegId { get; set; }

        public DateTimeOffset RegIdDate { get; set; }

        public string StatId { get; set; }

        public DateTimeOffset? StatIdDate { get; set; }

        public string Name { get; set; }

        public string ShortName { get; set; }

        public virtual int? ParentOrgLink { get; set; }

        public string TaxRegId { get; set; }

        public DateTimeOffset? TaxRegDate { get; set; }

        public int? RegistrationReasonId { get; set; }

        public virtual RegistrationReason RegistrationReason { get; set; }

        public string ExternalId { get; set; }

        public DateTimeOffset? ExternalIdDate { get; set; }

        public string ExternalIdType { get; set; }

        public string DataSource { get; set; }

        public string WebAddress { get; set; }

        public string TelephoneNo { get; set; }

        public string EmailAddress { get; set; }

        public int? ActualAddressId { get; set; }

        public virtual Address ActualAddress { get; set; }

        public int? PostalAddressId { get; set; }

        public virtual Address PostalAddress { get; set; }

        public bool FreeEconZone { get; set; }

        public int? NumOfPeopleEmp { get; set; }

        public int? Employees { get; set; }

        public int? EmployeesYear { get; set; }

        public DateTimeOffset? EmployeesDate { get; set; }

        public decimal? Turnover { get; set; }

        public DateTimeOffset? TurnoverDate { get; set; }

        public int? TurnoverYear { get; set; }

        public string Notes { get; set; }

        public bool? Classified { get; set; }

        public DateTimeOffset? StatusDate { get; set; }

        [MaxLength(25)]
        public string RefNo { get; set; }

        public virtual int? InstSectorCodeId { get; set; }

        public virtual SectorCode InstSectorCode { get; set; }

        public virtual int? LegalFormId { get; set; }

        public virtual LegalForm LegalForm { get; set; }

        public DateTimeOffset RegistrationDate { get; set; }

        public DateTimeOffset? LiqDate { get; set; }

        public string LiqReason { get; set; }

        public DateTimeOffset? SuspensionStart { get; set; }

        public DateTimeOffset? SuspensionEnd { get; set; }

        public string ReorgTypeCode { get; set; }

        public DateTimeOffset? ReorgDate { get; set; }

        public int? ReorgReferences { get; set; }

        public bool IsDeleted { get; set; }

        public abstract StatUnitTypes UnitType { get; }

        public int? ParentId { get; set; }

        public virtual StatisticalUnit Parent { get; set; }

        public DateTimeOffset StartPeriod { get; set; }

        public DateTimeOffset EndPeriod { get; set; }

        public virtual ICollection<ActivityStatisticalUnitHistory> ActivitiesUnits { get; set; } =
            new HashSet<ActivityStatisticalUnitHistory>();

        [NotMapped]
        [JsonIgnore]
        public IEnumerable<ActivityHistory> Activities
        {
            get => ActivitiesUnits.Select(v => v.Activity);
            set => throw new NotImplementedException();
        }

        [JsonIgnore]
        public virtual ICollection<PersonStatisticalUnitHistory> PersonsUnits { get; set; } =
            new HashSet<PersonStatisticalUnitHistory>();

        [NotMapped]
        [JsonIgnore]
        public IEnumerable<Person> Persons
        {
            get => PersonsUnits.Select(v => v.Person);
            set => throw new NotImplementedException();
        }

        public string UserId { get; set; }

        public ChangeReasons ChangeReason { get; set; }

        public string EditComment { get; set; }

        public int? SizeId { get; set; }

        [JsonIgnore]
        public virtual UnitSize Size { get; set; }

        public int? ForeignParticipationId { get; set; }

        public int? DataSourceClassificationId { get; set; }

        [JsonIgnore]
        public virtual DataSourceClassification DataSourceClassification { get; set; }

        public int? ReorgTypeId { get; set; }

        public int? UnitStatusId { get; set; }

        [JsonIgnore]
        public virtual ICollection<CountryStatisticalUnitHistory> ForeignParticipationCountriesUnits { get; set; } =
            new HashSet<CountryStatisticalUnitHistory>();

        [NotMapped]
        [JsonIgnore]
        public IEnumerable<Country> Countries
        {
            get => ForeignParticipationCountriesUnits.Select(v => v.Country);
            set => throw new NotImplementedException();
        }
    }
}
