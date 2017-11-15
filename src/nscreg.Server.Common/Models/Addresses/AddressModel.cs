namespace nscreg.Server.Common.Models.Addresses
{
    /// <summary>
    /// Модель адреса
    /// </summary>
    public class AddressModel
    {
        public int Id { get; set; }
        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string AddressPart3 { get; set; }
        public int RegionId { get; set; }
        public string GpsCoordinates { get; set; }
    }
}
