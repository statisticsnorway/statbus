using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;

namespace nscreg.Server.Models.StatUnits.Edit
{
    public class ActivityEditM
    {
        [Required]
        public int? Id { get; set; }
        [Required]
        public int? UnitId { get; set; }
        public int ActivityRevx { get; set; }
        public int ActivityRevy { get; set; }
        [DataType(DataType.Date)]
        public DateTime ActivityYear { get; set; }
        public ActivityTypes ActivityType { get; set; }
        public int Employees { get; set; }
        public decimal Turnover { get; set; }
        [Required]
        public int? UpdatedBy { get; set; }
    }
}
