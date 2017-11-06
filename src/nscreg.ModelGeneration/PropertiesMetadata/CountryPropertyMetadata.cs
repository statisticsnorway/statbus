using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Country metadata class
    /// </summary>
    public class CountryPropertyMetadata : PropertyMetadataBase
    {
        public CountryPropertyMetadata(string name, bool isRequired, IEnumerable<Country> value, string groupName = null, string localizeKey = null)
            : base(name, isRequired, localizeKey, groupName)
        {
            Value = value;
        }

        public IEnumerable<Country> Value { get; set; }

        public override PropertyType Selector => PropertyType.Countries;
    }
}
