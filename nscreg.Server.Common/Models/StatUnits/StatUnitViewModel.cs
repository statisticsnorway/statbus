using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.ModelGeneration;

namespace nscreg.Server.Common.Models.StatUnits
{
    public class StatUnitViewModel : ViewModelBase
    {
        public StatUnitTypes StatUnitType { get; set; }
        public int? Id { get; set; }
        public ICollection<string> DataAccess { get; set; }
    }
}
