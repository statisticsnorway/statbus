using nscreg.Utilities.Enums;

namespace nscreg.Server.Models.Dynamic.Property
{
    public class ReferencePropertyMetadata : PropertyMetadataBase
    {
        public ReferencePropertyMetadata(string name, bool isRequired, int? value, LookupEnum lookup) : base(name, isRequired)
        {
            Lookup = lookup;
            Value = value;
        }

        public int? Value { get; set; }
        public LookupEnum Lookup { get; set; }
        public override PropertyType Selector => PropertyType.Reference;

    }
}