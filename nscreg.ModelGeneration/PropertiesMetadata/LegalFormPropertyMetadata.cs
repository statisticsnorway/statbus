using nscreg.Data.Entities;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    public class LegalFormPropertyMetadata : PropertyMetadataBase
    {
        public LegalFormPropertyMetadata(string name, bool isRequired, LegalForm value, string groupName = null, string localizeKey = null)
            : base(name, isRequired, localizeKey, groupName)
        {
            Value = value;
        }

        public LegalForm Value { get; set; }

        public override PropertyType Selector => PropertyType.LegalForm;
    }
}
