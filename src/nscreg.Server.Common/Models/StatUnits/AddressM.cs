using nscreg.Resources.Languages;
using FluentValidation;
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
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }

        public bool IsEmpty()
            => string.IsNullOrEmpty(
                RegionId +
                AddressPart1 +
                AddressPart2 +
                AddressPart3 +
                Latitude +
                Longitude);

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
                   Latitude == a.Latitude &&
                   Longitude == a.Longitude;
        }

        public bool Equals(Address obj)
            => obj != null
               && AddressPart1 == obj.AddressPart1
               && AddressPart2 == obj.AddressPart2
               && AddressPart3 == obj.AddressPart3
               && RegionId == obj.RegionId
               && Latitude == obj.Latitude
               && Longitude == obj.Longitude;

        public override string ToString()
            => $"{AddressPart1} {AddressPart2} {AddressPart3}";
    }

    public class AddressMValidator : AbstractValidator<AddressM>
    {
        public AddressMValidator()
        {
            RuleFor(v => v.Latitude)
                .InclusiveBetween(-90, 90).When(x=> x.Latitude.HasValue).WithMessage(nameof(Resource.LatitudeValidationMessage));
            RuleFor(v => v.Longitude)
                .InclusiveBetween(-180, 180).When(x => x.Longitude.HasValue).WithMessage(nameof(Resource.LongitudeValidationMessage));
        }
    }
}
