using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.Lookup
{
    public interface IUnitVm
    {
        int Id { get; set; }
        StatUnitTypes Type { get; set; }
    }
}
