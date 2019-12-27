using System;
using nscreg.Utilities.Enums;

namespace nscreg.Utilities.Attributes
{
    /// <summary>
    /// Class atrebut reference links
    /// </summary>
    [AttributeUsage(AttributeTargets.Property)]
    public class ReferenceAttribute : Attribute
    {
        public LookupEnum Lookup { get; }
        public bool AllowMultiple { get; set; }

        public ReferenceAttribute(LookupEnum lookup)
        {
            Lookup = lookup;
        }
    }
}
