namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств строки
    /// </summary>
    public class StringPropertyMetadata : PropertyMetadataBase
    {
        public StringPropertyMetadata(
            string name, bool isRequired, string value, string groupName = null, string localizeKey = null, bool writable = false, string validationUrl = null)
            : base(name, isRequired, localizeKey, groupName, writable, validationUrl)
        {
            Value = value;
        }

        public string Value { get; set; }

        public override PropertyType Selector => PropertyType.String;
    }
}
