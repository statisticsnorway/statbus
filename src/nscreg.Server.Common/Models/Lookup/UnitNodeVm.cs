using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Lookup
{
    public class UnitNodeVm : UnitLookupVm
    {
        public bool Highlight { get; set; }
        public List<UnitNodeVm> Children { get; set; }
    }
}
