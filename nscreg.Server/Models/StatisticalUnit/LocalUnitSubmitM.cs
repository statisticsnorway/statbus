using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.StatisticalUnit
{
    public class LocalUnitSubmitM : StatisticalUnitSubmitM
    {
        public int LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
    }
}
