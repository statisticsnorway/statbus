using System;
using nscreg.Server.Models.StatisticalUnit.Submit;

namespace nscreg.Server.Models.StatisticalUnit
{
    public interface IStatisticalUnitsM
    {
        string Name { get; set; }
        AddressM Address { get; set; }
        AddressM ActualAddress { get; set; }
    }
}
