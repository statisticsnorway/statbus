using nscreg.Data.Entities;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    public class SectorCodePropertyMetadata : PropertyMetadataBase
    {
        public SectorCodePropertyMetadata(string name, bool isRequired, SectorCode value, string groupName = null, string localizeKey = null)
            : base(name, isRequired, localizeKey, groupName)
        {
            Value = value;
        }

        public SectorCode Value { get; set; }

        public override PropertyType Selector => PropertyType.SectorCode;
    }
}
