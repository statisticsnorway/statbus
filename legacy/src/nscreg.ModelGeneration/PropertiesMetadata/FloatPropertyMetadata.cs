namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Floating Point Property Metadata Class
    /// </summary>
    public class FloatPropertyMetadata : PropertyMetadataBase
    {
        public FloatPropertyMetadata(
            string name, bool isRequired, decimal? value, int order, string groupName = null, string localizeKey = null, bool writable = false, string popupLocalizedKey = null)
            : base(name, isRequired, order, localizeKey, groupName, writable, null, popupLocalizedKey)
        {
            Value = value;
        }

        public decimal? Value { get; set; }

        public override PropertyType Selector => PropertyType.Float;
    }
}
