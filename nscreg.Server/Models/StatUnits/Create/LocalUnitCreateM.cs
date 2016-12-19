using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.StatUnits.Create
{
    public class LocalUnitCreateM : StatUnitCreateM
    {
        public int LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
    }
}
