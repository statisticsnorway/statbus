using System;
using System.ComponentModel.DataAnnotations.Schema;

namespace nscreg.Data.Entities
{
    [Table("LocalUnit")]
    public class LocalUnit : StatisticalUnit
    {
        public int LegalUnitId { get; set; } //	ID of legal unit of which the unit belongs
        public DateTime LegalUnitIdDate { get; set; }    //	Date of assosciation with legal unit
    }
}
