using System;
using nscreg.Data.Constants;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    public class Activity
    {
        public int Id { get; set; }
        public DateTime IdDate { get; set; }
        [JsonIgnore]
        public int UnitId { get; set; }
        [JsonIgnore]
        public virtual StatisticalUnit Unit { get; set; }
        public int ActivityRevx { get; set; }
        public int ActivityRevy { get; set; }
        public DateTime ActivityYear { get; set; } //TODO: Replace to int
        public ActivityTypes ActivityType { get; set; }
        public int Employees { get; set; }
        public decimal Turnover { get; set; }
        [JsonIgnore]
        public int UpdatedBy { get; set; }
        [JsonIgnore]
        public DateTime UpdatedDate { get; set; }
    }
}