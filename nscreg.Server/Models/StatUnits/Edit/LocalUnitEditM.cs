using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.StatUnits.Base;

namespace nscreg.Server.Models.StatUnits.Edit
{
    public class LocalUnitEditM : StatUnitCreateEditBaseM
    {
        [Required]
        public int? RegId { get; set; }
        public int LegalUnitId { get; set; }

        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
        public int? EnterpriseUnitRegId { get; set; }
    }
}
