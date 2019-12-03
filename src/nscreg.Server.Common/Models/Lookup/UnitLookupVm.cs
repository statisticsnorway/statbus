using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.Lookup
{
    /// <summary>
    /// View unit search model
    /// </summary>
    public class UnitLookupVm : CodeLookupVm, IUnitVm
    {
        public StatUnitTypes Type { get; set; }
    }
}
