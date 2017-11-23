namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств числа с плавающей точкой
    /// </summary>
    public class FloatPropertyMetadata : PropertyMetadataBase
    {
        public FloatPropertyMetadata(
            string name, bool isRequired, decimal? value, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, localizeKey, groupName, writable)
        {
            Value = value;
        }

        public decimal? Value { get; set; }

        public override PropertyType Selector => PropertyType.Float;
    }
}
