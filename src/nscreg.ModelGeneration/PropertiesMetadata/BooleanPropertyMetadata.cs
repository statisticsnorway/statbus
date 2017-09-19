
namespace nscreg.ModelGeneration.PropertiesMetadata
{
    public class BooleanPropertyMetadata : PropertyMetadataBase
    {
        public BooleanPropertyMetadata(
            string name, bool isRequired, bool? value, string groupName = null, string localizeKey = null)
            : base(name, isRequired, localizeKey, groupName)
        {
            Value = value;
        }

        public bool? Value { get; set; }

        public override PropertyType Selector => PropertyType.Boolean;
    }
}
