using System.Collections.Generic;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность страна
    /// </summary>
    public class Country : LookupBase
    {
        public string Code { get; set; }
        public string IsoCode { get; set; }
        [JsonIgnore]
        public virtual ICollection<CountryStatisticalUnit> CountriesUnits { get; set; }
    }
}
