using System;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public class LocalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LocalUnit;
        public DateTime LegalUnitIdDate { get; set; }    //	Date of assosciation with legal unit
        public int LegalUnitId { get; set; } //	ID of legal unit of which the unit belongs
        public int? EnterpriseUnitRegId { get; set; }
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }

    }
}