using System.Collections.Generic;

namespace nscreg.Server.Models.StatUnits
{
    public interface IStatUnitM
    {
        string Name { get; set; }
        AddressM Address { get; set; }
        AddressM ActualAddress { get; set; }
        ICollection<string> DataAccess { get; set; }
    }
}
