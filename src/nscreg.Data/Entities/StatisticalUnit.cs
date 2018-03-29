using Newtonsoft.Json;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность стат. еденица
    /// </summary>
    public abstract class StatisticalUnit : IStatisticalUnit
    {
        [DataAccessCommon]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit)]
        public int RegId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public DateTime RegIdDate { get; set; }

        [DataAccessCommon]
        [Display(Order = 100, GroupName = GroupNames.StatUnitInfo)]
        [Utilities.Attributes.AsyncValidation(ValidationTypeEnum.StatIdUnique)]
        public string StatId { get; set; }

        [Display(Order = 110, GroupName = GroupNames.StatUnitInfo)]
        public DateTime? StatIdDate { get; set; }

        [DataAccessCommon]
        [Display(Order = 120, GroupName = GroupNames.StatUnitInfo)]
        public string Name { get; set; }

        [Display(Order = 130, GroupName = GroupNames.StatUnitInfo)]
        public string ShortName { get; set; }

        [SearchComponent]
        [Display(Order = 500, GroupName = GroupNames.LinkInfo)]
        public virtual int? ParentOrgLink { get; set; }

        [Display(Order = 150, GroupName = GroupNames.StatUnitInfo)]
        public string TaxRegId { get; set; }

        [Display(Order = 160, GroupName = GroupNames.StatUnitInfo)]
        public DateTime? TaxRegDate { get; set; }

        [Reference(LookupEnum.RegistrationReasonLookup)]
        [Display(Order = 220, GroupName = GroupNames.StatUnitInfo)]
        public int? RegistrationReasonId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual RegistrationReason RegistrationReason { get; set; }

        [Display(Order = 171, GroupName = GroupNames.StatUnitInfo)]
        public string ExternalId { get; set; }

        [Display(Order = 172, GroupName = GroupNames.StatUnitInfo)]
        public DateTime? ExternalIdDate { get; set; }

        [Display(Order = 173, GroupName = GroupNames.StatUnitInfo)]
        public int? ExternalIdType { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string DataSource { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? AddressId { get; set; }

        [Display(Order = 300, GroupName = GroupNames.ContactInfo)]
        public virtual Address Address { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string ContactPerson { get; set; }

        [Display(Order = 202, GroupName = GroupNames.ContactInfo)]
        public string WebAddress { get; set; }

        [Display(Order = 200, GroupName = GroupNames.ContactInfo)]
        public string TelephoneNo { get; set; }

        [Display(Order = 201, GroupName = GroupNames.ContactInfo)]
        public string EmailAddress { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ActualAddressId { get; set; }

        [Display(Order = 310, GroupName = GroupNames.ContactInfo)]
        public virtual Address ActualAddress { get; set; }

        [Display(Order = 470, GroupName = GroupNames.IndexInfo)]
        public bool FreeEconZone { get; set; }

        [Reference(LookupEnum.CountryLookup)]
        [Display(Order = 475, GroupName = GroupNames.IndexInfo)]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ForeignParticipationCountryId { get; set; }

        [Display(Order = 490, GroupName = GroupNames.IndexInfo)]
        public int? NumOfPeopleEmp { get; set; }

        [Display(Order = 200, GroupName = GroupNames.StatUnitInfo)]
        public int? Employees { get; set; }

        [Display(Order = 201, GroupName = GroupNames.StatUnitInfo)]
        public int? EmployeesYear { get; set; }

        [Display(Order = 202, GroupName = GroupNames.StatUnitInfo)]
        public DateTime? EmployeesDate { get; set; }

        [PopupLocalizedKey("InThousandsKGS")]
        [Display(Order = 180, GroupName = GroupNames.StatUnitInfo)]
        public decimal? Turnover { get; set; }

        [Display(Order = 560, GroupName = GroupNames.IndexInfo)]
        public DateTime? TurnoverDate { get; set; }

        [Display(Order = 190, GroupName = GroupNames.StatUnitInfo)]
        public int? TurnoverYear { get; set; }

        [Display(Order = 570, GroupName = GroupNames.IndexInfo)]
        public string Notes { get; set; }

        [Display(Order = 580, GroupName = GroupNames.IndexInfo)]
        public bool? Classified { get; set; }

        [Display(Order = 223, GroupName = GroupNames.StatUnitInfo)]
        public DateTime? StatusDate { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? RefNo { get; set; }

        public virtual int? InstSectorCodeId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual SectorCode InstSectorCode { get; set; }

        public virtual int? LegalFormId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual LegalForm LegalForm { get; set; }

        [Display(Order = 810, GroupName = GroupNames.RegistrationInfo)]
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime RegistrationDate { get; set; }

        [Display(Order = 811, GroupName = GroupNames.RegistrationInfo)]
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime? LiqDate { get; set; }

        [Display(Order = 812, GroupName = GroupNames.RegistrationInfo)]
        [NotMappedFor(ActionsEnum.Create)]
        public string LiqReason { get; set; }

        [Display(Order = 820, GroupName = GroupNames.RegistrationInfo)]
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime? SuspensionStart { get; set; }

        [Display(Order = 830, GroupName = GroupNames.RegistrationInfo)]
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime? SuspensionEnd { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string ReorgTypeCode { get; set; }

        [Display(Order = 840, GroupName = GroupNames.RegistrationInfo)]
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime? ReorgDate { get; set; }

        [SearchComponent]
        [Display(Order = 850, GroupName = GroupNames.RegistrationInfo)]
        [NotMappedFor(ActionsEnum.Create)]
        public int? ReorgReferences { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual Country ForeignParticipationCountry { get; set; }

        [Display(Order = 590)]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public StatUnitStatuses Status { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public bool IsDeleted { get; set; }

        public abstract StatUnitTypes UnitType { get; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ParentId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual StatisticalUnit Parent { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public DateTime StartPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public DateTime EndPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<ActivityStatisticalUnit> ActivitiesUnits { get; set; } =
            new HashSet<ActivityStatisticalUnit>();

        [NotMapped]
        [JsonIgnore]
        [Display(Order = 250, GroupName = GroupNames.RegistrationInfo)]
        public IEnumerable<Activity> Activities
        {
            get => ActivitiesUnits.Select(v => v.Activity);
            set => throw new NotImplementedException();
        }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<PersonStatisticalUnit> PersonsUnits { get; set; } =
            new HashSet<PersonStatisticalUnit>();

        [JsonIgnore]
        public IEnumerable<StatisticalUnit> PersonStatUnits => PersonsUnits
            .Where(pu => pu.StatUnitId != null).Select(pu => pu.StatUnit);

        [JsonIgnore]
        public IEnumerable<EnterpriseGroup> PersonEnterpriseGroups => PersonsUnits
            .Where(pu => pu.EnterpriseGroupId != null).Select(pu => pu.EnterpriseGroup);

        [NotMapped]
        [JsonIgnore]
        [Display(Order = 650, GroupName = GroupNames.RegistrationInfo)]
        public IEnumerable<Person> Persons
        {
            get => PersonsUnits.Select(v => v.Person);
            set => throw new NotImplementedException();
        }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string UserId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ChangeReasons ChangeReason { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string EditComment { get; set; }

        [Reference(LookupEnum.UnitSizeLookup)]
        [Display(Order = 205, GroupName = GroupNames.StatUnitInfo)]
        public int? Size { get; set; }

        [Reference(LookupEnum.ForeignParticipationLookup)]
        [Display(Order = 450, GroupName = GroupNames.IndexInfo)]
        public int? ForeignParticipationId { get; set; }

        [Reference(LookupEnum.DataSourceClassificationLookup)]
        [Display(Order = 221, GroupName = GroupNames.StatUnitInfo)]
        public int? DataSourceClassificationId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual DataSourceClassification DataSourceClassification { get; set; }

        [Reference(LookupEnum.ReorgTypeLookup)]
        [Display(Order = 680, GroupName = GroupNames.RegistrationInfo)]
        public int? ReorgTypeId { get; set; }

        [Reference(LookupEnum.UnitStatusLookup)]
        [Display(Order = 222, GroupName = GroupNames.StatUnitInfo)]
        public int? UnitStatusId { get; set; }

        [JsonIgnore]
        [Reference(LookupEnum.CountryLookup)]
        [Display(Order = 475, GroupName = GroupNames.IndexInfo)]
        public virtual ICollection<CountryStatisticalUnit> ForeignParticipationCountriesUnits { get; set; } =
            new HashSet<CountryStatisticalUnit>();

        [NotMapped]
        [JsonIgnore]
        [Display(Order = 425, GroupName = GroupNames.IndexInfo)]
        public IEnumerable<Country> Countries
        {
            get => ForeignParticipationCountriesUnits.Select(v => v.Country);
            set => throw new NotImplementedException();
        }
    }
}
