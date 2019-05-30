using Newtonsoft.Json;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Класс сущность история деятельности стат. еденицы
    /// </summary>
    public class ActivityStatisticalUnitHistory
    {
        public int UnitId { get; set; }
        [JsonIgnore]
        public virtual StatisticalUnitHistory Unit { get; set; }

        public int ActivityId { get; set; }
        public virtual Activity Activity { get; set; }
    }
}
