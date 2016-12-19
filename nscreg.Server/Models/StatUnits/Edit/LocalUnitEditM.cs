using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.StatUnits.Edit
{
    public class LocalUnitEditM : StatUnitEditM
    {
        public int LegalUnitId { get; set; }

        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
    }
}
