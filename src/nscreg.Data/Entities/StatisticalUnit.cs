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

        [NotMappedFor(ActionsEnum.Create)]
        public DateTime RegIdDate { get; set; }

        [DataAccessCommon]
        [Display(Order = 100, GroupName = GroupNames.StatUnitInfo)]
        public string StatId { get; set; }

        [Display(Order = 200, GroupName = GroupNames.StatUnitInfo)]
        public DateTime? StatIdDate { get; set; }

        [DataAccessCommon]
        [Display(Order = 120, GroupName = GroupNames.StatUnitInfo)]
        public string Name { get; set; }

        [Display(Order = 130, GroupName = GroupNames.StatUnitInfo)]
        public string ShortName { get; set; }

        [SearchComponent]
        [Display(Order = 125, GroupName = GroupNames.StatUnitInfo)]
        public int? ParentOrgLink { get; set; }

        [Display(Order = 150, GroupName = GroupNames.RegistrationInfo)]
        public string TaxRegId { get; set; }

        [Display(Order = 160, GroupName = GroupNames.RegistrationInfo)]
        public DateTime? TaxRegDate { get; set; }

        [Display(Order = 230, GroupName = GroupNames.RegistrationInfo)]
        public string RegistrationReason { get; set; }

        [Display(Order = 350, GroupName = GroupNames.RegistrationInfo)]
        public string ExternalId { get; set; }

        [Display(Order = 360, GroupName = GroupNames.RegistrationInfo)]
        public DateTime? ExternalIdDate { get; set; }

        [Display(Order = 370, GroupName = GroupNames.RegistrationInfo)]
        public int? ExternalIdType { get; set; }

        [Display(Order = 390, GroupName = GroupNames.RegistrationInfo)]
        public string DataSource { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? AddressId { get; set; }

        [Display(Order = 250, GroupName = GroupNames.ContactInfo)]
        public virtual Address Address { get; set; }

        [Display(Order = 260, GroupName = GroupNames.ContactInfo)]
        public string ContactPerson { get; set; }

        [Display(Order = 270, GroupName = GroupNames.ContactInfo)]
        public string WebAddress { get; set; }

        [Display(Order = 280, GroupName = GroupNames.ContactInfo)]
        public int PostalAddressId { get; set; }

        [Display(Order = 290, GroupName = GroupNames.ContactInfo)]
        public string TelephoneNo { get; set; }

        [Display(Order = 300, GroupName = GroupNames.ContactInfo)]
        public string EmailAddress { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ActualAddressId { get; set; }

        [Display(Order = 310, GroupName = GroupNames.ContactInfo)]
        public virtual Address ActualAddress { get; set; }

        [Display(Order = 460, GroupName = GroupNames.IndexInfo)]
        public string ForeignParticipation { get; set; }

        [Display(Order = 470, GroupName = GroupNames.IndexInfo)]
        public bool FreeEconZone { get; set; }

        [Reference(LookupEnum.CountryLookup)]
        [Display(Order = 475, GroupName = GroupNames.IndexInfo)]
        public int? ForeignParticipationCountryId { get; set; }

        [Display(Order = 490, GroupName = GroupNames.IndexInfo)]
        public int? NumOfPeopleEmp { get; set; }

        [Display(Order = 500, GroupName = GroupNames.IndexInfo)]
        public int? Employees { get; set; }

        [Display(Order = 520, GroupName = GroupNames.IndexInfo)]
        public int? EmployeesYear { get; set; }

        [Display(Order = 530, GroupName = GroupNames.IndexInfo)]
        public DateTime? EmployeesDate { get; set; }

        [Display(Order = 540, GroupName = GroupNames.IndexInfo)]
        public decimal? Turnover { get; set; }

        [Display(Order = 550, GroupName = GroupNames.IndexInfo)]
        public DateTime? TurnoverDate { get; set; }

        [Display(Order = 560, GroupName = GroupNames.IndexInfo)]
        public int? TurnoverYear { get; set; }

        [Display(Order = 570, GroupName = GroupNames.IndexInfo)]
        public string Notes { get; set; }

        [Display(Order = 580, GroupName = GroupNames.IndexInfo)]
        public string Classified { get; set; }

        [Display(Order = 600, GroupName = GroupNames.IndexInfo)]
        public DateTime? StatusDate { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public int? RefNo { get; set; }
       
        public virtual int? InstSectorCodeId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual SectorCode InstSectorCode { get; set; }

        public virtual int? LegalFormId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual LegalForm LegalForm { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public DateTime RegistrationDate { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public string LiqDate { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public string LiqReason { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public string SuspensionStart { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public string SuspensionEnd { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public string ReorgTypeCode { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public DateTime? ReorgDate { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public string ReorgReferences { get; set; }

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

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<ActivityStatisticalUnit> ActivitiesUnits { get; set; } =
            new HashSet<ActivityStatisticalUnit>();

        [NotMapped]
        [Display(Order = 650, GroupName = GroupNames.RegistrationInfo)]
        public IEnumerable<Activity> Activities
        {
            get => ActivitiesUnits.Select(v => v.Activity);
            set => throw new NotImplementedException();
        }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<PersonStatisticalUnit> PersonsUnits { get; set; } =
            new HashSet<PersonStatisticalUnit>();

        [NotMapped]
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

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<StatisticalUnitAnalysisError> AnalysisErrors { get; set; }
    }
}
