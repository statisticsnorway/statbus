using nscreg.Server.Models.Regions;

namespace nscreg.Server.Models.Addresses
{
    public class AddressModel
    {
        public int Id { get; set; }
        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string AddressPart3 { get; set; }
        public RegionM Region { get; set; }
        public string GpsCoordinates { get; set; }
    }
}
