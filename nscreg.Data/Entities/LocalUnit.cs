using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public class LocalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LocalUnit;
        [Display(Order = 400, GroupName = GroupNames.LinkInfo)]
        public DateTime LegalUnitIdDate { get; set; } //	Date of assosciation with legal unit

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 300, GroupName = GroupNames.LinkInfo)]
        public int? LegalUnitId { get; set; } //	ID of legal unit of which the unit belongs

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual LegalUnit LegalUnit { get; set; }

        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 500, GroupName = GroupNames.LinkInfo)]
        public int? EnterpriseUnitRegId { get; set; }

        [NotMappedFor(ActionsEnum.Create|ActionsEnum.Edit|ActionsEnum.View)]
        [Display(Order = 600)]
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }
    }
}