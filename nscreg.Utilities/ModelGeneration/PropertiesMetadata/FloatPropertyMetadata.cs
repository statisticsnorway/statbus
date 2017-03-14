namespace nscreg.Utilities.ModelGeneration.PropertiesMetadata
{
    public class FloatPropertyMetadata : PropertyMetadataBase
    {
        public FloatPropertyMetadata(
            string name, bool isRequired, decimal? value, string localizeKey = null)
            : base(name, isRequired, localizeKey)
        {
            Value = value;
        }

        public decimal? Value { get; set; }

        public override PropertyType Selector => PropertyType.Float;
    }
}
