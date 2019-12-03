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
    ///  Class entity group of enterprises
    /// </summary>
    public class EnterpriseGroup : IStatisticalUnit
    {
        public StatUnitTypes UnitType => StatUnitTypes.EnterpriseGroup;

        [DataAccessCommon]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit)]
        public int RegId { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 701)]
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime RegIdDate { get; set; }

        [DataAccessCommon]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 100)]
        [AsyncValidation(ValidationTypeEnum.StatIdUnique)]
        public string StatId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 105)]
        public DateTime? StatIdDate { get; set; }

        [DataAccessCommon]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 110)]
        public string Name { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 115)]
        public string ShortName { get; set; }

        [Display(Order = 705, GroupName = GroupNames.RegistrationInfo)]
        public DateTime RegistrationDate { get; set; }

        [Reference(LookupEnum.RegistrationReasonLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 140)]
        public int? RegistrationReasonId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 120)]
        public string TaxRegId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 125)]
        public DateTime? TaxRegDate { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 130)]
        public string ExternalId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 131)]
        public string ExternalIdType { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 132)]
        public DateTime? ExternalIdDate { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string DataSource { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public bool IsDeleted { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? AddressId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ActualAddressId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? PostalAddressId { get; set; }

        [Display(Order = 725, GroupName = GroupNames.RegistrationInfo)]
        public string EntGroupType { get; set; }

        [Display(Order = 520, GroupName = GroupNames.EconomicInformation)]
        public int? NumOfPeopleEmp { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 300)]
        public string TelephoneNo { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 301)]
        public string EmailAddress { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 302)]
        public string WebAddress { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 770)]
        public DateTime? LiqDateStart { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 780)]
        public DateTime? LiqDateEnd { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 710)]
        public string ReorgTypeCode { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 715)]
        public DateTime? ReorgDate { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 720)]
        public string ReorgReferences { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 303)]
        public string ContactPerson { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(GroupName = GroupNames.LinkInfo)]
        public DateTime StartPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(GroupName = GroupNames.LinkInfo)]
        public DateTime EndPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 760)]
        public string LiqReason { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 765)]
        public string SuspensionStart { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 775)]
        public string SuspensionEnd { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 521)]
        public int? Employees { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 522)]
        public int? EmployeesYear { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 523)]
        public DateTime? EmployeesDate { get; set; }

        [PopupLocalizedKey("InThousandsKGS")]
        [Display(GroupName = GroupNames.EconomicInformation, Order = 505)]
        public decimal? Turnover { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 510)]
        public int? TurnoverYear { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 515)]
        public DateTime? TurnoverDate { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 800)]
        public string Status { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 152)]
        public DateTime StatusDate { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 801)]
        public string Notes { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string UserId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ChangeReasons ChangeReason { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string EditComment { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 310)]
        public virtual Address Address { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 320)]
        public virtual Address ActualAddress { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 330)]
        public virtual Address PostalAddress { get; set; }

        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 200, GroupName = GroupNames.LinkInfo)]
        public virtual ICollection<EnterpriseUnit> EnterpriseUnits { get; set; } = new HashSet<EnterpriseUnit>();

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<PersonStatisticalUnit> PersonsUnits { get; set; } =
            new HashSet<PersonStatisticalUnit>();

        [JsonIgnore]
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
        [Display(GroupName = GroupNames.EconomicInformation, Order = 500)]
        public int? SizeId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual UnitSize Size { get; set; }

        [Reference(LookupEnum.DataSourceClassificationLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 150)]
        public int? DataSourceClassificationId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual DataSourceClassification DataSourceClassification { get; set; }

        [Reference(LookupEnum.ReorgTypeLookup)]
        [Display(GroupName = GroupNames.RegistrationInfo, Order = 700)]
        public int? ReorgTypeId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ReorgType ReorgType { get; set; }

        [Reference(LookupEnum.UnitStatusLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 151)]
        public int? UnitStatusId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual UnitStatus UnitStatus { get; set; }

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
