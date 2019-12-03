using nscreg.Utilities.Enums;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Link Property Metadata Class
    /// </summary>
    public class ReferencePropertyMetadata : PropertyMetadataBase
    {
        public ReferencePropertyMetadata(
            string name, bool isRequired, int? value, LookupEnum lookup, int order, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, order, localizeKey, groupName, writable)
        {
            Lookup = lookup;
            Value = value;
        }

        public int? Value { get; set; }

        public LookupEnum Lookup { get; set; }

        public override PropertyType Selector => PropertyType.Reference;
    }
}
