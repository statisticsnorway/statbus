using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public interface IStatisticalUnit
    {
        int RegId { get; set; }
        string Name { get; set; }
        int? AddressId { get; set; }
        int? ActualAddressId { get; set; }
        Address Address { get; set; }

        Address ActualAddress { get; set; }
        bool IsDeleted { get; set; }

        StatUnitTypes UnitType { get; }
    }
}