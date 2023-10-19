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
        public DateTimeOffset RegIdDate { get; set; }

        [DataAccessCommon]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.StatIdTooltip))]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 100)]
        [AsyncValidation(ValidationTypeEnum.StatIdUnique)]
        public string StatId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 105)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.StatIdDateTooltip))]
        public DateTimeOffset? StatIdDate { get; set; }

        [DataAccessCommon]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 110)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.StatNameTooltip))]
        public string Name { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 115)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ShortNameTooltip))]
        public string ShortName { get; set; }

        [Display(Order = 142, GroupName = GroupNames.StatUnitInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.RegDateTooltip))]
        public DateTimeOffset RegistrationDate { get; set; }

        [Reference(LookupEnum.RegistrationReasonLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 140)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.RegistrationReasonTooltip))]
        public int? RegistrationReasonId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 120)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.TaxRegIdTooltip))]
        public string TaxRegId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 125)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.TaxRegDateTooltip))]
        public DateTimeOffset? TaxRegDate { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 130)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ExternalIdTooltip))]
        public string ExternalId { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 131)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ExternalIdTypeTooltip))]
        public string ExternalIdType { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 132)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ExternalIdDateTooltip))]
        public DateTimeOffset? ExternalIdDate { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string DataSource { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public bool IsDeleted { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ActualAddressId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? PostalAddressId { get; set; }

        [Reference(LookupEnum.EntGroupTypeLookup)]
        [Display(Order = 725, GroupName = GroupNames.RegistrationInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EntGroupTypeIdTooltip))]
        public int? EntGroupTypeId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public EnterpriseGroupType EntGroupType { get; set; }

        [Display(Order = 520, GroupName = GroupNames.EconomicInformation)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.NumOfPeopleEmpTooltip))]
        public int? NumOfPeopleEmp { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 300)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.TelephoneNoTooltip))]
        public string TelephoneNo { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 301)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EmailAddressTooltip))]
        public string EmailAddress { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 302)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.WebAddressTooltip))]
        public string WebAddress { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 770)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.LiqDateStartTooltip))]
        public DateTimeOffset? LiqDateStart { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 780)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.LiqDateEndTooltip))]
        public DateTimeOffset? LiqDateEnd { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 710)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ReorgTypeCodeTooltip))]
        public string ReorgTypeCode { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 720)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ReorgReferencesTooltip))]
        public string ReorgReferences { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 303)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ContactPersonTooltip))]
        public string ContactPerson { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.StartPeriodTooltip))]
        public DateTimeOffset StartPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EndPeriodTooltip))]
        public DateTimeOffset EndPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 760)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.LiqReasonTooltip))]
        public string LiqReason { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 765)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.SuspensionStartTooltip))]
        public string SuspensionStart { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.LiquidationInfo, Order = 775)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.SuspensionStartTooltip))]
        public string SuspensionEnd { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 521)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EmployeesTooltip))]
        public int? Employees { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 522)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EmployeesYearTooltip))]
        public int? EmployeesYear { get; set; }

        [Display(GroupName = GroupNames.EconomicInformation, Order = 523)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EmployeesDateTooltip))]
        public DateTimeOffset? EmployeesDate { get; set; }

        [PopupLocalizedKey(nameof(Resources.Languages.Resource.TurnoverTooltip))]
        [Display(GroupName = GroupNames.EconomicInformation, Order = 505)]
        public decimal? Turnover { get; set; }

        [PopupLocalizedKey(nameof(Resources.Languages.Resource.TurnoverYearTooltip))]
        [Display(GroupName = GroupNames.EconomicInformation, Order = 510)]
        public int? TurnoverYear { get; set; }

        [PopupLocalizedKey(nameof(Resources.Languages.Resource.TurnoverDateTooltip))]
        [Display(GroupName = GroupNames.EconomicInformation, Order = 515)]
        public DateTimeOffset? TurnoverDate { get; set; }

        [Display(GroupName = GroupNames.StatUnitInfo, Order = 152)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.StatusDateTooltip))]
        public DateTimeOffset StatusDate { get; set; }

        [PopupLocalizedKey(nameof(Resources.Languages.Resource.NotesTooltip))]
        public string Notes { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string UserId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ChangeReasons ChangeReason { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string EditComment { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 320)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ActualAddressTooltip))]
        public virtual Address ActualAddress { get; set; }

        [Display(GroupName = GroupNames.ContactInfo, Order = 330)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.PostalAddressTooltip))]
        public virtual Address PostalAddress { get; set; }

        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 200, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EnterpriseUnitTooltip))]
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
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.UnitSizeTooltip))]
        public int? SizeId { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual UnitSize Size { get; set; }

        [Reference(LookupEnum.DataSourceClassificationLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 150)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.DataSourceClassificationTooltip))]
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
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ReorgTypeTooltip))]
        public int? ReorgTypeId { get; set; }

        [Display(GroupName = GroupNames.RegistrationInfo, Order = 702)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ReorgDateTooltip))]
        public DateTimeOffset? ReorgDate { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ReorgType ReorgType { get; set; }

        [Reference(LookupEnum.UnitStatusLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 151)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.UnitStatusTooltip))]
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
