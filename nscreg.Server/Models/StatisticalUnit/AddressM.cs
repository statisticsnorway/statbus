using System;

namespace nscreg.Server.Models.StatisticalUnit
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
        {
            return
                string.IsNullOrEmpty(AddressPart1 +
                                     AddressPart2 +
                                     AddressPart3 +
                                     AddressPart4 +
                                     AddressPart5 +
                                     GeographicalCodes +
                                     GpsCoordinates);
        }

        public override bool Equals(object obj)
        {
            var a = obj as AddressM;
            if (a == null) return false;
            return (AddressPart1 == a.AddressPart1 &&
                    AddressPart2 == a.AddressPart2 &&
                    AddressPart3 == a.AddressPart3 &&
                    AddressPart4 == a.AddressPart4 &&
                    AddressPart5 == a.AddressPart5 &&
                    GeographicalCodes == a.GeographicalCodes &&
                    GpsCoordinates == a.GpsCoordinates
            );
        }
    }
}
