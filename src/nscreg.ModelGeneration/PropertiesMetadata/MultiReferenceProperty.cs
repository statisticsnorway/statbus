using System.Collections.Generic;
using System.Linq;
using nscreg.Utilities.Enums;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств множественной ссылки
    /// </summary>
    public class MultiReferenceProperty : PropertyMetadataBase
    {
        public MultiReferenceProperty(
            string name, IEnumerable<int> ids, LookupEnum lookup, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, false, localizeKey, groupName, writable)
        {
            Value = ids.ToArray();
            Lookup = lookup;
        }

        public int[] Value { get; set; }

        public LookupEnum Lookup { get; set; }

        public override PropertyType Selector => PropertyType.MultiReference;
    }
}
