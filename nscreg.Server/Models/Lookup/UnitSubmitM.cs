using nscreg.Data.Constants;

namespace nscreg.Server.Models.Lookup
{
    public class UnitSubmitM : IUnitVm
    {
        public int Id { get; set; }
        public StatUnitTypes Type { get; set; }
    }
}
