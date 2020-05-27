using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity legal unity
    /// </summary>
    public class LegalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LegalUnit;

        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 200, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey("EnterpriseUnitRegIdTooltip")]
        public int? EnterpriseUnitRegId { get; set; }

        [Display(Order = 201, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey("EntRegIdDateTooltip")]
        public DateTime? EntRegIdDate { get; set; }

        [Reference(LookupEnum.LegalFormLookup)]
        [Display(Order = 150, GroupName = GroupNames.StatUnitInfo)]
        [PopupLocalizedKey("LegalFormIdTooltip")]
        public override int? LegalFormId
        {
            get => base.LegalFormId;
            set => base.LegalFormId = value;
        }

        [Reference(LookupEnum.SectorCodeLookup)]
        [Display(Order = 155, GroupName = GroupNames.StatUnitInfo)]
        [PopupLocalizedKey("InstSectorCodeIdTooltip")]
        public override int? InstSectorCodeId
        {
            get => base.InstSectorCodeId;
            set => base.InstSectorCodeId = value;
        }

        [Display(Order = 892, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey("MarketTooltip")]
        public bool Market { get; set; }
        [Column(nameof(TotalCapital))]
        [Display(Order = 845, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey("TotalCapitalTooltip")]
        public string TotalCapital { get; set; }
        [Column(nameof(MunCapitalShare))]
        [Display(Order = 825, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey("MunCapitalShareTooltip")]
        public string MunCapitalShare { get; set; }
        [Column(nameof(StateCapitalShare))]
        [Display(Order = 830, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey("StateCapitalShareTooltip")]
        public string StateCapitalShare { get; set; }
        [Column(nameof(PrivCapitalShare))]
        [Display(Order = 820, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey("PrivCapitalShareTooltip")]
        public string PrivCapitalShare { get; set; }
        [Column(nameof(ForeignCapitalShare))]
        [Display(Order = 835, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey("ForeignCapitalShareTooltip")]
        public string ForeignCapitalShare { get; set; }
        [Column(nameof(ForeignCapitalCurrency))]
        [Display(Order = 840, GroupName = GroupNames.CapitalInfo)]
        [PopupLocalizedKey("ForeignCapitalCurrencyTooltip")]
        public string ForeignCapitalCurrency { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }

        [Reference(LookupEnum.LocalUnitLookup)]
        [Display(GroupName = GroupNames.LinkInfo, Order = 202)]
        public virtual ICollection<LocalUnit> LocalUnits { get; set; } = new HashSet<LocalUnit>();

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [UsedByServerSide]
        public string HistoryLocalUnitIds { get; set; }

    }
}
