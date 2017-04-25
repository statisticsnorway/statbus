using nscreg.Data.Constants;

namespace nscreg.Server.Models.Lookup
{
    public interface IUnitVm
    {
        int Id { get; set; }
        StatUnitTypes Type { get; set; }
    }
}
