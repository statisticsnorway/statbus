using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
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
        [PopupLocalizedKey("StatIdTooltip")]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 100)]
        [AsyncValidation(ValidationTypeEnum.StatIdUnique)]
        public string StatId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 105)]
        [PopupLocalizedKey("StatIdDateTooltip")]
        public DateTime? StatIdDate { get; set; }

        [DataAccessCommon]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 110)]
        [PopupLocalizedKey("StatNameTooltip")]
        public string Name { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 115)]
        [PopupLocalizedKey("ShortNameTooltip")]
        public string ShortName { get; set; }

        [Display(Order = 705, GroupName = GroupNames.RegistrationInfo)]
        [PopupLocalizedKey("RegDateTooltip")]
        public DateTime RegistrationDate { get; set; }

        [Reference(LookupEnum.RegistrationReasonLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 140)]
        [PopupLocalizedKey("RegistrationReasonTooltip")]
        public int? RegistrationReasonId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 120)]
        [PopupLocalizedKey("TaxRegIdTooltip")]
        public string TaxRegId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 125)]
        [PopupLocalizedKey("TaxRegDateTooltip")]
        public DateTime? TaxRegDate { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 130)]
        [PopupLocalizedKey("ExternalIdTooltip")]
        public string ExternalId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 131)]
        [PopupLocalizedKey("ExternalIdTypeTooltip")]
        public string ExternalIdType { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 132)]
        [PopupLocalizedKey("ExternalIdDateTooltip")]
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

        [Reference(LookupEnum.EntGroupTypeLookup)]
        [Display(Order = 725, GroupName = GroupNames.RegistrationInfo)]
        [PopupLocalizedKey("EntGroupTypeIdTooltip")]
        public int? EntGroupTypeId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public EnterpriseGroupType EntGroupType { get; set; }

        [Display(Order = 520, GroupName = GroupNames.EconomicInformation)]
        [PopupLocalizedKey("NumOfPeopleEmpTooltip")]
        public int? NumOfPeopleEmp { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 300)]
        [PopupLocalizedKey("TelephoneNoTooltip")]
        public string TelephoneNo { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 301)]
        [PopupLocalizedKey("EmailAddressTooltip")]
        public string EmailAddress { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 302)]
        [PopupLocalizedKey("WebAddressTooltip")]
        public string WebAddress { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 770)]
        [PopupLocalizedKey("LiqDateStartTooltip")]
        public DateTime? LiqDateStart { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 780)]
        [PopupLocalizedKey("LiqDateEndTooltip")]
        public DateTime? LiqDateEnd { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 710)]
        [PopupLocalizedKey("ReorgTypeCodeTooltip")]
        public string ReorgTypeCode { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 715)]
        [PopupLocalizedKey("ReorgDateTooltip")]
        public DateTime? ReorgDate { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 720)]
        [PopupLocalizedKey("ReorgReferencesTooltip")]
        public string ReorgReferences { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 303)]
        [PopupLocalizedKey("ContactPersonTooltip")]
        public string ContactPerson { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey("StartPeriodTooltip")]
        public DateTime StartPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey("EndPeriodTooltip")]
        public DateTime EndPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 760)]
        [PopupLocalizedKey("LiqReasonTooltip")]
        public string LiqReason { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 765)]
        [PopupLocalizedKey("SuspensionStartTooltip")]
        public string SuspensionStart { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 775)]
        [PopupLocalizedKey("SuspensionStartTooltip")]
        public string SuspensionEnd { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 521)]
        [PopupLocalizedKey("EmployeesTooltip")]
        public int? Employees { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 522)]
        [PopupLocalizedKey("EmployeesYearTooltip")]
        public int? EmployeesYear { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 523)]
        [PopupLocalizedKey("EmployeesDateTooltip")]
        public DateTime? EmployeesDate { get; set; }

        [PopupLocalizedKey("TurnoverTooltip")]
        [Display(GroupName = GroupNames.EconomicInformation, Order = 505)]
        public decimal? Turnover { get; set; }

        [PopupLocalizedKey("TurnoverYearTooltip")]
        [Display(GroupName = GroupNames.EconomicInformation, Order = 510)]
        public int? TurnoverYear { get; set; }

        [PopupLocalizedKey("TurnoverDateTooltip")]
        [Display(GroupName = GroupNames.EconomicInformation, Order = 515)]
        public DateTime? TurnoverDate { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 152)]
        [PopupLocalizedKey("StatusDateTooltip")]
        public DateTime StatusDate { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 801)]
        [PopupLocalizedKey("NotesTooltip")]
        public string Notes { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string UserId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ChangeReasons ChangeReason { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string EditComment { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 310)]
        [PopupLocalizedKey("AddressTooltip")]
        public virtual Address Address { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 320)]
        [PopupLocalizedKey("ActualAddressTooltip")]
        public virtual Address ActualAddress { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 330)]
        [PopupLocalizedKey("PostalAddressTooltip")]
        public virtual Address PostalAddress { get; set; }

        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 200, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey("EnterpriseUnitTooltip")]
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

        [Reference(LookupEnum.UnitSizeLookup)]
        [Display(GroupName = GroupNames.EconomicInformation, Order = 500)]
        [PopupLocalizedKey("UnitSizeTooltip")]
        public int? SizeId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual UnitSize Size { get; set; }

        [Reference(LookupEnum.DataSourceClassificationLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 150)]
        [PopupLocalizedKey("DataSourceClassificationTooltip")]
        public int? DataSourceClassificationId { get; set; }

        [NotMapped]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? InstSectorCodeId
        {
            get => null;
            set { }
        }

        [NotMapped]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? LegalFormId
        {
            get => null;
            set { }
        }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual DataSourceClassification DataSourceClassification { get; set; }

        [Reference(LookupEnum.ReorgTypeLookup)]
        [Display(GroupName = GroupNames.RegistrationInfo, Order = 700)]
        [PopupLocalizedKey("ReorgTypeTooltip")]
        public int? ReorgTypeId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ReorgType ReorgType { get; set; }

        [Reference(LookupEnum.UnitStatusLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 151)]
        [PopupLocalizedKey("UnitStatusTooltip")]
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
