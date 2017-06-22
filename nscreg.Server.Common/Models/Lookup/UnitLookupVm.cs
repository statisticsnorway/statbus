using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.Lookup
{
    public class UnitLookupVm : CodeLookupVm, IUnitVm
    {
        public StatUnitTypes Type { get; set; }
    }
}
