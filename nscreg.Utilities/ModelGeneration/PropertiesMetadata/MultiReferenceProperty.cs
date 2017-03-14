using System.Collections.Generic;
using System.Linq;
using nscreg.Utilities.Enums;

namespace nscreg.Utilities.ModelGeneration.PropertiesMetadata
{
    public class MultiReferenceProperty : PropertyMetadataBase
    {
        public MultiReferenceProperty(
            string name, IEnumerable<int> ids, LookupEnum lookup, string localizeKey = null)
            : base(name, false, localizeKey)
        {
            Value = ids.ToArray();
            Lookup = lookup;
        }

        public int[] Value { get; set; }

        public LookupEnum Lookup { get; set; }

        public override PropertyType Selector => PropertyType.MultiReference;
    }
}
