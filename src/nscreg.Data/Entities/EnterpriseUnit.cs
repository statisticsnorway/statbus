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
    ///  Entity class Enterprise Unit
    /// </summary>
    public class EnterpriseUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.EnterpriseUnit;

        [Reference(LookupEnum.EnterpriseGroupLookup)]
        [Display(Order = 210, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EnterpriseGroupTooltip))]
        public int? EntGroupId { get; set; }

        [Display(Order = 220, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EntGroupIdDateTooltip))]
        public DateTimeOffset? EntGroupIdDate { get; set; }

        [SearchComponent]
        [Display(Order = 205, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ParentOrgLinkTooltip))]
        public override int? ParentOrgLink { get; set; }

        [Reference(LookupEnum.SectorCodeLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 150)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.InstSectorCodeIdTooltip))]
        public override int? InstSectorCodeId
        {
            get => base.InstSectorCodeId;
            set => base.InstSectorCodeId = value;
        }

        [Display(Order = 892, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.CommercialTooltip))]
        public bool Commercial { get; set; }
        [Column(nameof(TotalCapital))]
        [Display(Order = 845, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.TotalCapitalTooltip))]
        public string TotalCapital { get; set; }
        [Column(nameof(MunCapitalShare))]
        [Display(Order = 825, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.MunCapitalShareTooltip))]
        public string MunCapitalShare { get; set; }
        [Column(nameof(StateCapitalShare))]
        [Display(Order = 830, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.StateCapitalShareTooltip))]
        public string StateCapitalShare { get; set; }
        [Column(nameof(PrivCapitalShare))]
        [Display(Order = 820, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.PrivCapitalShareTooltip))]
        public string PrivCapitalShare { get; set; }
        [Column(nameof(ForeignCapitalShare))]
        [Display(Order = 835, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ForeignCapitalShareTooltip))]
        public string ForeignCapitalShare { get; set; }
        [Column(nameof(ForeignCapitalCurrency))]
        [Display(Order = 840, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.ForeignCapitalCurrencyTooltip))]
        public string ForeignCapitalCurrency { get; set; }

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 200, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.LegalUnitsTooltip))]
        public virtual ICollection<LegalUnit> LegalUnits { get; set; } = new HashSet<LegalUnit>();

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [UsedByServerSide]
        public string HistoryLegalUnitIds { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public override int? LegalFormId
        {
            get => null;
            set { }
        }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public EnterpriseGroupRole EntGroupRole { get; set; }

        [Reference(LookupEnum.EntGroupRoleLookup)]
        [Display(Order = 215, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey(nameof(Resources.Languages.Resource.EntGroupRoleTooltip))]
        public int? EntGroupRoleId { get; set; }
    }
}
