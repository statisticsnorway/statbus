using nscreg.Data.Entities;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Address Property Metadata Class
    /// </summary>
    public class AddressPropertyMetadata :PropertyMetadataBase
    {
        public AddressPropertyMetadata(string name, bool isRequired, Address value, int order, string groupName = null, string localizeKey = null, bool writable = false)
            : base(name, isRequired, order, localizeKey, groupName, writable)
        {
            Value = value;
        }

        public Address Value { get; set; }

        public override PropertyType Selector => PropertyType.Addresses;
    }

}
