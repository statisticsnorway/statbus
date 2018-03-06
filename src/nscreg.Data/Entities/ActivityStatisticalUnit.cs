using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность деятельность стат. еденицы
    /// </summary>
    public class ActivityStatisticalUnit
    {
        public int UnitId { get; set; }
        [JsonIgnore]
        public virtual StatisticalUnit Unit { get; set; }

        public int ActivityId { get; set; }
        public virtual Activity Activity { get; set; }
    }
}
