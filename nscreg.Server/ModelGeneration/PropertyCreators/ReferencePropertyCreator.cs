using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Server.Models.Dynamic.Property;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    public class ReferencePropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propertyInfo)
        {
            var type = propertyInfo.PropertyType;
            return
                !(type.GetTypeInfo().IsGenericType && type.GetGenericTypeDefinition() == typeof(ICollection<>)) &&
                propertyInfo.IsDefined(typeof(ReferenceAttribute));
        }

        public override PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj)
        {
            var lookup = ((ReferenceAttribute) propertyInfo.GetCustomAttribute(typeof(ReferenceAttribute))).Lookup;

            return new ReferencePropertyMetadata(propertyInfo.Name, !propertyInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propertyInfo, obj), lookup);
        }
    }
}