using System.Reflection;
using nscreg.Server.Models.Dynamic.Property;
using nscreg.Utilities;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    internal class BooleanPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propertyInfo)
        {
            return propertyInfo.PropertyType == typeof(bool) || propertyInfo.PropertyType == typeof(bool?);
        }

        public override PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj)
        {
            return new BooleanPropertyMetadata(propertyInfo.Name, propertyInfo.PropertyType.IsNullable(),
                GetAtomicValue<bool?>(propertyInfo, obj));
        }
    }
}