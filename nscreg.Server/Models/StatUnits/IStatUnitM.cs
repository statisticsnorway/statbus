using nscreg.Utilities.Enums;

namespace nscreg.Server.Models.StatUnits
{
    public interface IStatUnitM
    {
        string Name { get; set; }
        AddressM Address { get; set; }
        AddressM ActualAddress { get; set; }
    }
}
