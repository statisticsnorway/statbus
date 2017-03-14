namespace nscreg.Utilities.ModelGeneration.PropertiesMetadata
{
    public class BooleanPropertyMetadata : PropertyMetadataBase
    {
        public BooleanPropertyMetadata(
            string name, bool isRequired, bool? value, string localizeKey = null)
            : base(name, isRequired, localizeKey)
        {
            Value = value;
        }

        public bool? Value { get; set; }

        public override PropertyType Selector => PropertyType.Boolean;
    }
}
