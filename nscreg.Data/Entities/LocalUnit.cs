using System;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public class LocalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LocalUnit;
        public DateTime LegalUnitIdDate { get; set; } //	Date of assosciation with legal unit

        [Reference(LookupEnum.LegalUnitLookup)]
        public int LegalUnitId { get; set; } //	ID of legal unit of which the unit belongs

        [Reference(LookupEnum.EnterpriseUnitLookup)]
        public int? EnterpriseUnitRegId { get; set; }

        [NotMappedFor(ActionsEnum.Create|ActionsEnum.Edit|ActionsEnum.View)]
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }
    }
}