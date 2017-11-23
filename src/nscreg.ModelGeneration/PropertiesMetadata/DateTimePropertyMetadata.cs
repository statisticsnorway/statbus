using System;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств даты
    /// </summary>
    public class DateTimePropertyMetadata : PropertyMetadataBase
    {
        public DateTimePropertyMetadata(
            string name, bool isRequired, DateTime? value, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, localizeKey, groupName, writable)
        {
            Value = value == DateTime.MinValue ? null : value;
        }

        public DateTime? Value { get; set; }

        public override PropertyType Selector => PropertyType.DateTime;
    }
}
