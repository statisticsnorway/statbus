using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class StringPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo) => propInfo.PropertyType == typeof(string);

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new StringPropertyMetadata(
                propInfo.Name,
                false,
                GetAtomicValue<string>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName);
    }
}
