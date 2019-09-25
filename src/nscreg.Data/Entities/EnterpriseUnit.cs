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
    ///  Класс сущность предприятие
    /// </summary>
    public class EnterpriseUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.EnterpriseUnit;

        [Reference(LookupEnum.EnterpriseGroupLookup)]
        [Display(Order = 210, GroupName = GroupNames.LinkInfo)]
        public int? EntGroupId { get; set; }

        [Display(Order = 220, GroupName = GroupNames.LinkInfo)]
        public DateTime EntGroupIdDate { get; set; }

        [Display(Order = 215, GroupName = GroupNames.LinkInfo)]
        public string EntGroupRole { get; set; }

        [SearchComponent]
        [Display(Order = 205, GroupName = GroupNames.LinkInfo)]
        public override int? ParentOrgLink { get; set; }

        [Reference(LookupEnum.SectorCodeLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo, Order = 150)]
        public override int? InstSectorCodeId
        {
            get => base.InstSectorCodeId;
            set => base.InstSectorCodeId = value;
        }

        [Display(Order = 892, GroupName = GroupNames.CapitalInfo)]
        public bool Commercial { get; set; }
        [Column(nameof(TotalCapital))]
        [Display(Order = 845, GroupName = GroupNames.CapitalInfo)]
        public string TotalCapital { get; set; }
        [Column(nameof(MunCapitalShare))]
        [Display(Order = 825, GroupName = GroupNames.CapitalInfo)]
        public string MunCapitalShare { get; set; }
        [Column(nameof(StateCapitalShare))]
        [Display(Order = 830, GroupName = GroupNames.CapitalInfo)]
        public string StateCapitalShare { get; set; }
        [Column(nameof(PrivCapitalShare))]
        [Display(Order = 820, GroupName = GroupNames.CapitalInfo)]
        public string PrivCapitalShare { get; set; }
        [Column(nameof(ForeignCapitalShare))]
        [Display(Order = 835, GroupName = GroupNames.CapitalInfo)]
        public string ForeignCapitalShare { get; set; }
        [Column(nameof(ForeignCapitalCurrency))]
        [Display(Order = 840, GroupName = GroupNames.CapitalInfo)]
        public string ForeignCapitalCurrency { get; set; }

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 200, GroupName = GroupNames.LinkInfo)]
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

    }
}
