namespace nscreg.Server.Common.Models.Addresses
{
    /// <summary>
    /// Address Model
    /// </summary>
    public class AddressModel
    {
        public int Id { get; set; }
        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string AddressPart3 { get; set; }
        public int RegionId { get; set; }
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
    }
}
