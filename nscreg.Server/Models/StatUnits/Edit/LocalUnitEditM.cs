using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.StatUnits.Edit
{
    public class LocalUnitEditM : StatUnitModelBase
    {
        [Required]
        public int? RegId { get; set; }
        public int LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
        public int? EnterpriseUnitRegId { get; set; }
    }
}
