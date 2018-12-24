using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Класс сущность история персоны стат. единицы
    /// </summary>
    public class PersonStatisticalUnitHistory
    {
        public int UnitId { get; set; }
        public virtual StatisticalUnitHistory Unit { get; set; }

        public int? StatUnitId { get; set; }
        public virtual StatisticalUnitHistory StatUnit { get; set; }

        public int? EnterpriseGroupId { get; set; }
        public virtual EnterpriseGroupHistory EnterpriseGroup { get; set; }

        public int? PersonId { get; set; }
        public virtual Person Person { get; set; }

        public PersonTypes PersonType { get; set; }
    }
}
