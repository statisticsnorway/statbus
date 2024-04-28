namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Integer Properties Metadata Class
    /// </summary>
    public class IntegerPropertyMetadata : PropertyMetadataBase
    {
        public IntegerPropertyMetadata(
            string name, bool isRequired, int? value, int order, string groupName = null, string localizeKey = null, bool writable = false, string popupLocalizedKey = null)
            : base(name, isRequired, order, localizeKey, groupName, writable, null, popupLocalizedKey)
        {
            Value = value;
        }

        public int? Value { get; set; }

        public override PropertyType Selector => PropertyType.Integer;
    }
}
