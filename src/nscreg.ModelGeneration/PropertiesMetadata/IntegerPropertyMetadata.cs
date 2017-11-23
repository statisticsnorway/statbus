namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств целого числа
    /// </summary>
    public class IntegerPropertyMetadata : PropertyMetadataBase
    {
        public IntegerPropertyMetadata(
            string name, bool isRequired, int? value, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, localizeKey, groupName, writable)
        {
            Value = value;
        }

        public int? Value { get; set; }

        public override PropertyType Selector => PropertyType.Integer;
    }
}
