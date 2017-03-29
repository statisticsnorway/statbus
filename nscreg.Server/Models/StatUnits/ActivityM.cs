using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.Models.StatUnits
{
    public class ActivityM
    {
        [NotCompare]
        public int? Id { get; set; }
        public int ActivityRevx { get; set; }
        public int ActivityRevy { get; set; }
        public int ActivityYear { get; set; }
        public ActivityTypes ActivityType { get; set; }
        public int Employees { get; set; }
        public decimal Turnover { get; set; }
    }
}
