using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность правовая единца
    /// </summary>
    public class LegalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LegalUnit;

        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 100, GroupName = GroupNames.LinkInfo)]
        public int? EnterpriseUnitRegId { get; set; }

        [Display(Order = 200, GroupName = GroupNames.RegistrationInfo)]
        public DateTime? EntRegIdDate { get; set; }

        [Reference(LookupEnum.LegalFormLookup)]
        [Display(Order = 180, GroupName = GroupNames.RegistrationInfo)]
        public override int? LegalFormId
        {
            get => base.LegalFormId;
            set => base.LegalFormId = value;
        }

        [Reference(LookupEnum.SectorCodeLookup)]
        [Display(Order = 190, GroupName = GroupNames.StatUnitInfo)]
        public override int? InstSectorCodeId
        {
            get => base.InstSectorCodeId;
            set => base.InstSectorCodeId = value;
        }

        [Display(Order = 400, GroupName = GroupNames.CapitalInfo)]
        public bool Market { get; set; }

        [Display(Order = 480, GroupName = GroupNames.CapitalInfo)]
        public string TotalCapital { get; set; }

        [Display(Order = 410, GroupName = GroupNames.CapitalInfo)]
        public string MunCapitalShare { get; set; }

        [Display(Order = 420, GroupName = GroupNames.CapitalInfo)]
        public string StateCapitalShare { get; set; }

        [Display(Order = 430, GroupName = GroupNames.CapitalInfo)]
        public string PrivCapitalShare { get; set; }

        [Display(Order = 440, GroupName = GroupNames.CapitalInfo)]
        public string ForeignCapitalShare { get; set; }

        [Display(Order = 450, GroupName = GroupNames.CapitalInfo)]
        public string ForeignCapitalCurrency { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string Founders { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string Owner { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }

        [Reference(LookupEnum.LocalUnitLookup)]
        [Display(GroupName = GroupNames.LinkInfo)]
        public virtual ICollection<LocalUnit> LocalUnits { get; set; } = new HashSet<LocalUnit>();

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string HistoryLocalUnitIds { get; set; }

        [Display(Order = 460, GroupName = GroupNames.IndexInfo)]
        public new string ForeignParticipation { get; set; }

        [Display(Order = 470, GroupName = GroupNames.IndexInfo)]
        public new bool FreeEconZone { get; set; }

        [Display(Order = 580, GroupName = GroupNames.IndexInfo)]
        public new string Classified { get; set; }
    }
}
