using nscreg.Utilities.Enums;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств ссылки
    /// </summary>
    public class ReferencePropertyMetadata : PropertyMetadataBase
    {
        public ReferencePropertyMetadata(
            string name, bool isRequired, int? value, LookupEnum lookup, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, localizeKey, groupName, writable)
        {
            Lookup = lookup;
            Value = value;
        }

        public int? Value { get; set; }

        public LookupEnum Lookup { get; set; }

        public override PropertyType Selector => PropertyType.Reference;
    }
}
