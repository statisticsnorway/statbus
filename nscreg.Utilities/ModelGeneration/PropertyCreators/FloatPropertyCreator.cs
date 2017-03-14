using System.Reflection;
using nscreg.Utilities.ModelGeneration.PropertiesMetadata;

namespace nscreg.Utilities.ModelGeneration.PropertyCreators
{
    public class FloatPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => propInfo.PropertyType == typeof(decimal) || propInfo.PropertyType == typeof(decimal?);

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new FloatPropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<decimal?>(propInfo, obj));
    }
}
