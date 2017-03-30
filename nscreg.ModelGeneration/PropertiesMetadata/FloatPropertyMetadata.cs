namespace nscreg.ModelGeneration.PropertiesMetadata
{
    public class FloatPropertyMetadata : PropertyMetadataBase
    {
        public FloatPropertyMetadata(
            string name, bool isRequired, decimal? value, string groupName = null, string localizeKey = null)
            : base(name, isRequired, localizeKey, groupName)
        {
            Value = value;
        }

        public decimal? Value { get; set; }

        public override PropertyType Selector => PropertyType.Float;
    }
}
