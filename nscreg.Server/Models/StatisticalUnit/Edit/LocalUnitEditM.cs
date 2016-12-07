using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.StatisticalUnit.Edit
{
    public class LocalUnitEditM : StatisticalUnitEditM
    {
        public int LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
    }
}
