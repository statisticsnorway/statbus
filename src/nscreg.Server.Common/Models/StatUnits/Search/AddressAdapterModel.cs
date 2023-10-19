using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class AddressAdapterModel
    {
        public AddressAdapterModel(StatUnitSearchView statUnit)
        {
            ActualAddressPart1 = statUnit.ActualAddressPart1;
            ActualAddressPart2 = statUnit.ActualAddressPart2;

        }
        public string ActualAddressPart1 { get; set; }
        public string ActualAddressPart2 { get; set; }
        public string FullPath { get; set; }
        public string FullPathLanguage1 { get; set; }
        public string FullPathLanguage2 { get; set; }
    }
}
