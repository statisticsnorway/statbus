using System.Reflection;
using nscreg.Utilities.ModelGeneration.Properties;

namespace nscreg.Utilities.ModelGeneration.PropertyCreators
{
    public class BooleanPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => propInfo.PropertyType == typeof(bool) || propInfo.PropertyType == typeof(bool?);

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new BooleanPropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<bool?>(propInfo, obj));
    }
}
