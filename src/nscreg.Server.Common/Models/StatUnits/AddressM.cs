using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.StatUnits
{
#pragma warning disable CS0659 // Type overrides Object.Equals(object o) but does not override Object.GetHashCode()
    public class AddressM
#pragma warning restore CS0659 // Type overrides Object.Equals(object o) but does not override Object.GetHashCode()
    {
        public int Id { get; set; }
        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string AddressPart3 { get; set; }
        public int RegionId { get; set; }
        public string GpsCoordinates { get; set; }

        public bool IsEmpty()
            => string.IsNullOrEmpty(
                AddressPart1 +
                AddressPart2 +
                AddressPart3 +
                GpsCoordinates);

        #pragma warning disable 659
        public override bool Equals(object obj)
        #pragma warning restore 659
        {
            var a = obj as AddressM;
            return a != null &&
                   AddressPart1 == a.AddressPart1 &&
                   AddressPart2 == a.AddressPart2 &&
                   AddressPart3 == a.AddressPart3 &&
                   RegionId == a.RegionId &&
                   GpsCoordinates == a.GpsCoordinates;
        }

        public bool Equals(Address obj)
            => obj != null
               && AddressPart1 == obj.AddressPart1
               && AddressPart2 == obj.AddressPart2
               && AddressPart3 == obj.AddressPart3
               && RegionId == obj.RegionId
               && GpsCoordinates == obj.GpsCoordinates;

        public override string ToString()
            => $"{AddressPart1} {AddressPart2} {AddressPart3}";
    }
}
