using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    public class ActivityPropertyMetadata : PropertyMetadataBase
    {
        public ActivityPropertyMetadata(string name, bool isRequired, IEnumerable<Activity> value, string localizeKey = null)
            : base(name, isRequired, localizeKey)
        {
            Value = value;
        }

        public IEnumerable<Activity> Value { get; set; }

        public override PropertyType Selector => PropertyType.Activities;
    }
}