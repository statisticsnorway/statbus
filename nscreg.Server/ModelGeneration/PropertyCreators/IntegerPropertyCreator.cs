using System.Reflection;
using nscreg.Server.Models.Dynamic.Property;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    internal class IntegerPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propertyInfo)
        {
            return !propertyInfo.IsDefined(typeof(ReferenceAttribute)) &&
                   (propertyInfo.PropertyType == typeof(int) || propertyInfo.PropertyType == typeof(int?));
        }

        public override PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj)
        {
            return new IntegerPropertyMetadata(propertyInfo.Name, !propertyInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propertyInfo, obj));
        }
    }
}