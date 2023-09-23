using System;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Date Property Metadata Class
    /// </summary>
    public class DateTimeOffsetPropertyMetadata : PropertyMetadataBase
    {
        public DateTimeOffsetPropertyMetadata(
            string name, bool isRequired, DateTimeOffset? value, int order, string groupName = null, string localizeKey = null, bool writable = false, string popupLocalizedKey = null)
            : base(name, isRequired, order, localizeKey, groupName, writable, null, popupLocalizedKey)
        {
            Value = value == DateTimeOffset.MinValue ? null : value;
        }

        public DateTimeOffset? Value { get; set; }

        public override PropertyType Selector => PropertyType.DateTimeOffset;
    }
}
