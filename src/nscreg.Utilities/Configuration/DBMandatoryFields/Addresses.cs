namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Address class with required fields
    /// </summary>
    public class Addresses
    {
        public bool AddressPart1 { get; set; }
        public bool AddressPart2 { get; set; }
        public bool AddressPart3 { get; set; }
        public bool GeographicalCodes { get; set; }
        public bool Latitude { get; set; }
        public bool Longitude { get; set; }
    }
}
