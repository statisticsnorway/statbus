namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Класс Адресов с обязательными полями 
    /// </summary>
    public class Addresses
    {
        public bool AddressId { get; set; }
        public bool AddressPart1 { get; set; }
        public bool AddressPart2 { get; set; }
        public bool AddressPart3 { get; set; }
        public bool GeographicalCodes { get; set; }
        public bool GpsCoordinates { get; set; }
    }
}
