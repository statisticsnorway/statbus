using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Entities;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    public class AddressPropertyMetadata :PropertyMetadataBase
    {
        public AddressPropertyMetadata(string name, bool isRequired, Address value, string localizeKey = null)
            : base(name, isRequired, localizeKey)
        {
            Value = value;
        }

        public Address Value { get; set; }

        public override PropertyType Selector => PropertyType.Addresses;
    }

}
