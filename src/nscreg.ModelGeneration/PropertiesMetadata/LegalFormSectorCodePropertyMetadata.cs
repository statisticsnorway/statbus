namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств правовой формы собственности
    /// </summary>
    public class LegalFormSectorCodePropertyMetadata : PropertyMetadataBase
    {
        public LegalFormSectorCodePropertyMetadata(string name, bool isRequired, int? value, int order, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, order, localizeKey, groupName, writable)
        {
            Value = value;
        }

        public int? Value { get; set; }

        public override PropertyType Selector => PropertyType.SearchComponent;
    }
}
