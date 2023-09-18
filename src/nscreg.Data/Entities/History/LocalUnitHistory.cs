using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Class entity history of the local unit
    /// </summary>
    public class LocalUnitHistory : StatisticalUnitHistory
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LocalUnit;

        public int? LegalUnitId { get; set; }

        public DateTimeOffset LegalUnitIdDate { get; set; }

        public override int? InstSectorCodeId
        {
            get => null;
            set { }
        }

        public override int? LegalFormId
        {
            get => null;
            set { }
        }

        public override int? ParentOrgLink { get; set; }
    }
}
