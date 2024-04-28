using Newtonsoft.Json;
using nscreg.Data.Constants;
using System;
using System.Collections.Generic;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Class entity activity history stat. units
    /// </summary>
    public class ActivityStatisticalUnitHistory
    {
        public int UnitId { get; set; }
        [JsonIgnore]
        public virtual StatisticalUnitHistory Unit { get; set; }

        public int ActivityId { get; set; }
        //public virtual Activity Activity { get; set; }
        public virtual ActivityHistory Activity { get; set; }
    }

    public class ActivityHistory : IModelWithId
    {
        public int Id { get; set; }
        public DateTimeOffset IdDate { get; set; }
        [JsonIgnore]
        public virtual ICollection<ActivityStatisticalUnitHistory> ActivitiesUnits { get; set; }
        public int ActivityCategoryId { get; set; }
        public virtual ActivityCategory ActivityCategory { get; set; }
        public int? ActivityYear { get; set; }
        public ActivityTypes ActivityType { get; set; }
        public int? Employees { get; set; }
        public decimal? Turnover { get; set; }
        [JsonIgnore]
        public string UpdatedBy { get; set; }
        [JsonIgnore]
        public virtual User UpdatedByUser { get; set; }
        public DateTimeOffset UpdatedDate { get; set; }
        public int ParentId { get; set; }
    }
}
