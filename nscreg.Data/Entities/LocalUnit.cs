using System;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public class LocalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LocalUnit;
        public int LegalUnitId { get; set; } //	ID of legal unit of which the unit belongs
        public DateTime LegalUnitIdDate { get; set; }    //	Date of assosciation with legal unit
    }
}