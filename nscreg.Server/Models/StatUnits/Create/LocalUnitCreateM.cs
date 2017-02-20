using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.StatUnits.Base;

namespace nscreg.Server.Models.StatUnits.Create
{
    public class LocalUnitCreateM : StatUnitCreateEditBaseM
    {
        public int LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
        public int? EnterpriseUnitRegId { get; set; }
    }
}
