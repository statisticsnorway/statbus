using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.Lookup
{
    /// <summary>
    /// View unit model
    /// </summary>
    public class UnitSubmitM : IUnitVm
    {
        public int Id { get; set; }
        public StatUnitTypes Type { get; set; }
    }
}
