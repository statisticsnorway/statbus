using System;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    public class DateTimePropertyMetadata : PropertyMetadataBase
    {
        public DateTimePropertyMetadata(
            string name, bool isRequired, DateTime? value, string groupName = null, string localizeKey = null)
            : base(name, isRequired, localizeKey, groupName)
        {
            Value = value == DateTime.MinValue ? null : value;
        }

        public DateTime? Value { get; set; }

        public override PropertyType Selector => PropertyType.DateTime;
    }
}
