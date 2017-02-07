using System;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public class Activity
    {
        public int Id { get; set; }
        public DateTime IdDate { get; set; }
        public int UnitId { get; set; }
        public virtual StatisticalUnit Unit { get; set; }
        public int ActivityRevx { get; set; }
        public int ActivityRevy { get; set; }
        public DateTime ActivityYear { get; set; }
        public ActivityTypes ActivityType { get; set; }
        public int Employees { get; set; }
        public decimal Turnover { get; set; }
        public int UpdatedBy { get; set; }
        public DateTime UpdatedDate { get; set; }
    }
}