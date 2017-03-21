namespace nscreg.ModelGeneration.PropertiesMetadata
{
    public class CollectionPropertyMetadata : PropertyMetadataBase
    {
        public CollectionPropertyMetadata(string name, bool isRequired, string localizeKey = null)
            : base(name, isRequired, localizeKey)
        {
        }

        public override PropertyType Selector => PropertyType.Reference;
    }
}