using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class AddressAdapterModel
    {
        public AddressAdapterModel(StatUnitSearchView statUnit)
        {
            AddressPart1 = statUnit.AddressPart1;
            AddressPart2 = statUnit.AddressPart2;
            AddressPart3 = statUnit.AddressPart3;
        }

        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string AddressPart3 { get; set; }
        public string RegionFullPath { get; set; }
    }
}
