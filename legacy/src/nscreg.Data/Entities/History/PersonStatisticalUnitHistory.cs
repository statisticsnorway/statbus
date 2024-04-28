using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Class entity story person stat. units
    /// </summary>
    public class PersonStatisticalUnitHistory
    {
        public int UnitId { get; set; }
        public virtual StatisticalUnitHistory Unit { get; set; }

        public int? EnterpriseGroupId { get; set; }

        public int? PersonId { get; set; }
        public virtual Person Person { get; set; }

        public int? PersonTypeId { get; set; }
        public virtual PersonType PersonType { get; set; }
    }
}
