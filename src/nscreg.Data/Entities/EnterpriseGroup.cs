using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность группа предприятий
    /// </summary>
    public class EnterpriseGroup : IStatisticalUnit
    {
        public StatUnitTypes UnitType => StatUnitTypes.EnterpriseGroup;

        [DataAccessCommon]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit)]
        public int RegId { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 60)]
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime RegIdDate { get; set; }

        [DataAccessCommon]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 10)]
        [AsyncValidation(ValidationTypeEnum.StatIdUnique)]
        public string StatId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 20)]
        public DateTime? StatIdDate { get; set; }

        [DataAccessCommon]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 30)]
        public string Name { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 40)]
        public string ShortName { get; set; }

        [Display(Order = 110, GroupName = GroupNames.RegistrationInfo)]
        public DateTime RegistrationDate { get; set; }

        [Reference(LookupEnum.RegistrationReasonLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 130)]
        public int? RegistrationReasonId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 60)]
        public string TaxRegId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 70)]
        public DateTime? TaxRegDate { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 80)]
        public string ExternalId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 81)]
        public int? ExternalIdType { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 82)]
        public DateTime? ExternalIdDate { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string DataSource { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public bool IsDeleted { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ParentId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? AddressId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ActualAddressId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? PostalAddressId { get; set; }

        [Display(Order = 50, GroupName = GroupNames.StatUnitInfo)]
        public string EntGroupType { get; set; }

        [Display(Order = 55, GroupName = GroupNames.StatUnitInfo)]
        public int? NumOfPeopleEmp { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 20)]
        public string TelephoneNo { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 21)]
        public string EmailAddress { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 22)]
        public string WebAddress { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.ContactInfo, Order = 50)]
        public DateTime? LiqDateStart { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.ContactInfo, Order = 60)]
        public DateTime? LiqDateEnd { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 70)]
        public string ReorgTypeCode { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 80)]
        public DateTime? ReorgDate { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 90)]
        public string ReorgReferences { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 100)]
        public string ContactPerson { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(GroupName = GroupNames.LinkInfo)]
        public DateTime StartPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(GroupName = GroupNames.LinkInfo)]
        public DateTime EndPeriod { get; set; }

        [Display(GroupName = GroupNames.LiquidationInfo, Order = 30)]
        public string LiqReason { get; set; }

        [Display(GroupName = GroupNames.LiquidationInfo, Order = 40)]
        public string SuspensionStart { get; set; }

        [Display(GroupName = GroupNames.LiquidationInfo, Order = 50)]
        public string SuspensionEnd { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 110)]
        public int? Employees { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 111)]
        public int? EmployeesYear { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 112)]
        public DateTime? EmployeesDate { get; set; }

        [PopupLocalizedKey("InThousandsKGS")]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 90)]
        public decimal? Turnover { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 100)]
        public int? TurnoverYear { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 80)]
        public DateTime? TurnoverDate { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 90)]
        public string Status { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 133)]
        public DateTime StatusDate { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 80)]
        public string Notes { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string UserId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ChangeReasons ChangeReason { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string EditComment { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 30)]
        public virtual Address Address { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 40)]
        public virtual Address ActualAddress { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 45)]
        public virtual Address PostalAddress { get; set; }

        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 40, GroupName = GroupNames.LinkInfo)]
        public virtual ICollection<EnterpriseUnit> EnterpriseUnits { get; set; } = new HashSet<EnterpriseUnit>();

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<PersonStatisticalUnit> PersonsUnits { get; set; } =
            new HashSet<PersonStatisticalUnit>();


        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual RegistrationReason RegistrationReason { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [UsedByServerSide]
        public string HistoryEnterpriseUnitIds { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? RegMainActivityId
        {
            get => null;
            // ReSharper disable once ValueParameterNotUsed
            set { }
        }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? InstSectorCodeId
        {
            get => null;
            set { }
        }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? LegalFormId
        {
            get => null;
            set { }
        }

        [Reference(LookupEnum.UnitSizeLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 120)]
        public int? Size { get; set; }

        [Reference(LookupEnum.DataSourceClassificationLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 131)]
        public int? DataSourceClassificationId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual DataSourceClassification DataSourceClassification { get; set; }

        [Reference(LookupEnum.ReorgTypeLookup)]
        [Display(GroupName = GroupNames.RegistrationInfo, Order = 50)]
        public int? ReorgTypeId { get; set; }

        [Reference(LookupEnum.UnitStatusLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 132)]
        public int? UnitStatusId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public SectorCode InstSectorCode { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ICollection<ActivityStatisticalUnit> ActivitiesUnits { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ICollection<CountryStatisticalUnit> ForeignParticipationCountriesUnits { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public LegalForm LegalForm { get; set; }
    }
}
