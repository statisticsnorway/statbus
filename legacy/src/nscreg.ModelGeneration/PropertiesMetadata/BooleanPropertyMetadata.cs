
namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Boolean property metadata class
    /// </summary>
    public class BooleanPropertyMetadata : PropertyMetadataBase
    {
        public BooleanPropertyMetadata(
            string name, bool isRequired, bool? value, int order, string groupName = null, string localizeKey = null, bool writable = false, string popupLocalizedKey = null)
            : base(name, isRequired, order, localizeKey, groupName, writable, popupLocalizedKey:popupLocalizedKey)
        {
            Value = value;
        }

        public bool? Value { get; set; }

        public override PropertyType Selector => PropertyType.Boolean;
    }
}
