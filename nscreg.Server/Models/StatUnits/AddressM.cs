using nscreg.Data.Entities;

namespace nscreg.Server.Models.StatUnits
{
    public class AddressM
    {
        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string AddressPart3 { get; set; }
        public string AddressPart4 { get; set; }
        public string AddressPart5 { get; set; }
        public string GeographicalCodes { get; set; }
        public string GpsCoordinates { get; set; }

        public bool IsEmpty()
            => string.IsNullOrEmpty(
                AddressPart1 +
                AddressPart2 +
                AddressPart3 +
                AddressPart4 +
                AddressPart5 +
                GeographicalCodes +
                GpsCoordinates);

        public override bool Equals(object obj)
        {
            var a = obj as AddressM;
            return a != null &&
                AddressPart1 == a.AddressPart1 &&
                AddressPart2 == a.AddressPart2 &&
                AddressPart3 == a.AddressPart3 &&
                AddressPart4 == a.AddressPart4 &&
                AddressPart5 == a.AddressPart5 &&
                GeographicalCodes == a.GeographicalCodes &&
                GpsCoordinates == a.GpsCoordinates;
        }

        public bool Equals(Address obj)
        {
            if (obj == null) return false;
            return (AddressPart1 == obj.AddressPart1 &&
                    AddressPart2 == obj.AddressPart2 &&
                    AddressPart3 == obj.AddressPart3 &&
                    AddressPart4 == obj.AddressPart4 &&
                    AddressPart5 == obj.AddressPart5 &&
                    GeographicalCodes == obj.GeographicalCodes &&
                    GpsCoordinates == obj.GpsCoordinates
            );
        }

        public override int GetHashCode()
            => unchecked(((((((
            17 + AddressPart1.GetHashCode()) * 117)
            ^ AddressPart2.GetHashCode() * 217)
            ^ AddressPart3.GetHashCode() * 317)
            ^ AddressPart4.GetHashCode() * 417)
            ^ AddressPart5.GetHashCode() * 517)
            ^ GeographicalCodes.GetHashCode() * 617)
            ^ GpsCoordinates.GetHashCode() * 717;

        public override string ToString()
            => $"{AddressPart1} {AddressPart2} {AddressPart3} {AddressPart4} {AddressPart5}";
    }
}
