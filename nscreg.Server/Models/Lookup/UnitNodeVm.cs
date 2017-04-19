using System.Collections.Generic;

namespace nscreg.Server.Models.Lookup
{
    public class UnitNodeVm : UnitLookupVm
    {
        public bool Highlight { get; set; }
        public List<UnitNodeVm> Children { get; set; }
    }
}
