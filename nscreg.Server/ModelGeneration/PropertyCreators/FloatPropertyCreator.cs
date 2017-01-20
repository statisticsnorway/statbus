using System.Reflection;
using nscreg.Server.Models.Dynamic.Property;
using nscreg.Utilities;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    internal class FloatPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propertyInfo)
        {
            return propertyInfo.PropertyType == typeof(decimal) || propertyInfo.PropertyType == typeof(decimal?);
        }

        public override PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj)
        {
            return new FloatPropertyMetadata(propertyInfo.Name, propertyInfo.PropertyType.IsNullable(),
                GetAtomicValue<decimal?>(propertyInfo, obj));
        }
    }
}