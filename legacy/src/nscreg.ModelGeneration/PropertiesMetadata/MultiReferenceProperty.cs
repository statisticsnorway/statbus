using System.Collections.Generic;
using System.Linq;
using nscreg.Utilities.Enums;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Multiple Link Property Metadata Class
    /// </summary>
    public class MultiReferenceProperty : PropertyMetadataBase
    {
        public MultiReferenceProperty(
            string name, IEnumerable<int> ids, LookupEnum lookup, bool mandatory, int order, string groupName = null, string localizeKey = null, bool writable = false, string popupLocalizedKey = null)
            : base(name, mandatory, order, localizeKey, groupName, writable, popupLocalizedKey: popupLocalizedKey)
        {
            Value = ids.ToArray();
            Lookup = lookup;
        }

        public int[] Value { get; set; }

        public LookupEnum Lookup { get; set; }

        public override PropertyType Selector => PropertyType.MultiReference;
    }
}
