using System.Collections.Generic;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity country
    /// </summary>
    public class Country : CodeLookupBase
    {
        public string IsoCode { get; set; }
        [JsonIgnore]
        public virtual ICollection<CountryStatisticalUnit> CountriesUnits { get; set; }
    }
}
