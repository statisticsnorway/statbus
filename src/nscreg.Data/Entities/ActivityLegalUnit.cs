using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity activity stat. units
    /// </summary>
    public class ActivityLegalUnit
    {
        public int UnitId { get; set; }
        [JsonIgnore]
        public virtual LegalUnit Unit { get; set; }

        public int ActivityId { get; set; }
        public virtual Activity Activity { get; set; }
    }
}
