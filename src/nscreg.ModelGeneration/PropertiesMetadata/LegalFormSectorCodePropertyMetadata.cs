namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Property metadata class
    /// </summary>
    public class LegalFormSectorCodePropertyMetadata : PropertyMetadataBase
    {
        public LegalFormSectorCodePropertyMetadata(string name, bool isRequired, int? value, int order, string groupName = null, string localizeKey = null, bool writable = false, string popupLocalizedKey = null)
            : base(name, isRequired, order, localizeKey, groupName, writable, popupLocalizedKey: popupLocalizedKey)
        {
            Value = value;
        }

        public int? Value { get; set; }

        public override PropertyType Selector => PropertyType.SearchComponent;
    }
}
