using System.Reflection;
using nscreg.Utilities.ModelGeneration.PropertiesMetadata;

namespace nscreg.Utilities.ModelGeneration.PropertyCreators
{
    public class StringPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo) => propInfo.PropertyType == typeof(string);

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new StringPropertyMetadata(
                propInfo.Name,
                false,
                GetAtomicValue<string>(propInfo, obj));
    }
}
