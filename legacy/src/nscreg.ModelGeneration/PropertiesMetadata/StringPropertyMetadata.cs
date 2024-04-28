namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// String Property Metadata Class
    /// </summary>
    public class StringPropertyMetadata : PropertyMetadataBase
    {
        public StringPropertyMetadata(
            string name, bool isRequired, string value, int order, string groupName = null, string localizeKey = null, bool writable = false, string validationUrl = null, string popupLocalizedKey = null)
            : base(name, isRequired, order, localizeKey, groupName, writable, validationUrl, popupLocalizedKey)
        {
            Value = value;
        }

        public string Value { get; set; }

        public override PropertyType Selector => PropertyType.String;
    }
}
