using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.StatUnits
{
    public class LocalUnitSubmitM : StatUnitSubmitM
    {
        public int LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
    }
}
