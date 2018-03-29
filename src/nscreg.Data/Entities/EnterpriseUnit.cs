using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность предприятие
    /// </summary>
    public class EnterpriseUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.EnterpriseUnit;

        [Reference(LookupEnum.EnterpriseGroupLookup)]
        [Display(Order = 320, GroupName = GroupNames.LinkInfo)]
        public int? EntGroupId { get; set; }

        [Display(Order = 800, GroupName = GroupNames.RegistrationInfo)]
        public DateTime EntGroupIdDate { get; set; }

        [Display(Order = 500, GroupName = GroupNames.LinkInfo)]
        public string EntGroupRole { get; set; }

        [SearchComponent]
        [Display(Order = 270, GroupName = GroupNames.LinkInfo)]
        public override int? ParentOrgLink { get; set; }

        [Reference(LookupEnum.SectorCodeLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo)]
        public override int? InstSectorCodeId
        {
            get => base.InstSectorCodeId;
            set => base.InstSectorCodeId = value;
        }

        [Display(Order = 380, GroupName = GroupNames.RegistrationInfo)]
        public bool Commercial { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 400)]
        public string TotalCapital { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 490)]
        public string MunCapitalShare { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 500)]
        public string StateCapitalShare { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 510)]
        public string PrivCapitalShare { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 520)]
        public string ForeignCapitalShare { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo, Order = 530)]
        public string ForeignCapitalCurrency { get; set; }

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 260, GroupName = GroupNames.LinkInfo)]
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
