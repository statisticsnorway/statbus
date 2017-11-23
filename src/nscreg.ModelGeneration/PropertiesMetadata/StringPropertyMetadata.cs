namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств строки
    /// </summary>
    public class StringPropertyMetadata : PropertyMetadataBase
    {
        public StringPropertyMetadata(
            string name, bool isRequired, string value, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, localizeKey, groupName, writable)
        {
            Value = value;
        }

        public string Value { get; set; }

        public override PropertyType Selector => PropertyType.String;
    }
}
