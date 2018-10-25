using System.Collections.Generic;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Models.StatUnits
{
    public interface IStatUnitM
    {
        string StatId { get; set; }
        string Name { get; set; }
        AddressM Address { get; set; }
        AddressM ActualAddress { get; set; }
        AddressM PostalAddress { get; set; }
        DataAccessPermissions DataAccess { get; set; }
        ChangeReasons ChangeReason { get; set; }
        string EditComment { get; set; }
    }
}
