using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    /// Binding entity with statistical unit and country history
    /// </summary>
    public class CountryStatisticalUnitHistory
    {
        public int UnitId { get; set; }
        public virtual StatisticalUnitHistory Unit { get; set; }

        public int CountryId { get; set; }
        public virtual Country Country { get; set; }

        public int Id => CountryId;
    }
}
