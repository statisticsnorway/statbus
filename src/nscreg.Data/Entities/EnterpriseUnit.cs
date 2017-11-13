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
        [Display(Order = 70, GroupName = GroupNames.LinkInfo)]
        public int? EntGroupId { get; set; }

        [Display(Order = 800, GroupName = GroupNames.RegistrationInfo)]
        public DateTime EntGroupIdDate { get; set; }

        [Display(Order = 90, GroupName = GroupNames.StatUnitInfo)]
        public string EntGroupRole { get; set; }

        [Reference(LookupEnum.SectorCodeLookup)]
        [Display(GroupName = GroupNames.StatUnitInfo)]
        public override int? InstSectorCodeId
        {
            get => base.InstSectorCodeId;
            set => base.InstSectorCodeId = value;
        }

        [Display(Order = 380, GroupName = GroupNames.RegistrationInfo)]
        public bool Commercial { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo)]
        public string TotalCapital { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo)]
        public string MunCapitalShare { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo)]
        public string StateCapitalShare { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo)]
        public string PrivCapitalShare { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo)]
        public string ForeignCapitalShare { get; set; }

        [Display(GroupName = GroupNames.CapitalInfo)]
        public string ForeignCapitalCurrency { get; set; }

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 320, GroupName = GroupNames.LinkInfo)]
        public virtual ICollection<LegalUnit> LegalUnits { get; set; } = new HashSet<LegalUnit>();

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string HistoryLegalUnitIds { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public override int? LegalFormId
        {
            get => null;
            set { }
        }

        [Display(Order = 460, GroupName = GroupNames.IndexInfo)]
        public new string ForeignParticipation { get; set; }

        [Display(Order = 470, GroupName = GroupNames.IndexInfo)]
        public new bool FreeEconZone { get; set; }

        [Display(Order = 580, GroupName = GroupNames.IndexInfo)]
        public new string Classified { get; set; }
    }
}
