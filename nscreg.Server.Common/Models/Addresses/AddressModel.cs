namespace nscreg.Server.Common.Models.Addresses
{
    public class AddressModel
    {
        public int Id { get; set; }
        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string AddressPart3 { get; set; }
        public string AddressPart4 { get; set; }
        public string AddressPart5 { get; set; }
        public string AddressDetails { get; set; }
        public string GeographicalCodes { get; set; }
        public string GpsCoordinates { get; set; }
    }
}
