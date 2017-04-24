using System;
using nscreg.Data.Constants;

namespace nscreg.Server.Models.Lookup
{
    public class UnitLookupVm : CodeLookupVm, IUnitVm
    {
        public StatUnitTypes Type { get; set; }
    }
}
