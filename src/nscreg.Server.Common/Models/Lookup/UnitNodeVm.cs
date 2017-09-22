using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Lookup
{
    /// <summary>
    /// Вью модель единицы узла
    /// </summary>
    public class UnitNodeVm : UnitLookupVm
    {
        public bool Highlight { get; set; }
        public List<UnitNodeVm> Children { get; set; }
    }
}
