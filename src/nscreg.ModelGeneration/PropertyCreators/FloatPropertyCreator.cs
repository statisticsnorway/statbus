using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class FloatPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => propInfo.PropertyType == typeof(decimal) || propInfo.PropertyType == typeof(decimal?);

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new FloatPropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<decimal?>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName);
    }
}
