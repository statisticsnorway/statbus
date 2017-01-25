using nscreg.Data.Constants;
using nscreg.Server.Models.Infrastructure;

namespace nscreg.Server.Models.StatUnits
{
    public class StatUnitViewModel : ViewModelBase
    {
        public StatUnitTypes StatUnitType { get; set; }
        public int? Id { get; set; }
    }
}