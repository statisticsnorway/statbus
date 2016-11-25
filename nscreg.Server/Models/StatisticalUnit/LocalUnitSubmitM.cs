using System;

namespace nscreg.Server.Models.StatisticalUnit
{
    public class LocalUnitSubmitM : StatisticalUnitSubmitM
    {
        public int LegalUnitId { get; set; }
        public DateTime LegalUnitIdDate { get; set; }
    }
}
