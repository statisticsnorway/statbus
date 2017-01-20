using System.Collections.Generic;
using System.Linq;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Models.Dynamic.Property
{
    public class MultiReferencePropery : PropertyMetadataBase
    {
        public MultiReferencePropery(string name, IEnumerable<int> ids, LookupEnum lookup): base(name, false)
        {
            Value = ids.ToArray();
            Lookup = lookup;
        }

        public int[] Value { get; set; }
        public LookupEnum Lookup { get; set; }
        public override PropertyType Selector => PropertyType.MultiReference;

    }
}