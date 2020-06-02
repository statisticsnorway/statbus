using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class AddressAdapterModel
    {
        public AddressAdapterModel(StatUnitSearchView statUnit)
        {
            AddressPart1 = statUnit.AddressPart1;
            AddressPart2 = statUnit.AddressPart2;

        }
        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string FullPath { get; set; }
        public string FullPathLanguage1 { get; set; }
        public string FullPathLanguage2 { get; set; }
    }
}
