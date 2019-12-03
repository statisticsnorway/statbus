using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Activity property metadata class
    /// </summary>
    public class ActivityPropertyMetadata : PropertyMetadataBase
    {
        public ActivityPropertyMetadata(string name, bool isRequired, IEnumerable<Activity> value, int order, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, order, localizeKey, groupName, writable)
        {
            Value = value;
        }

        public IEnumerable<Activity> Value { get; set; }

        public override PropertyType Selector => PropertyType.Activities;
    }
}
