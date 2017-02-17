using System.Collections.Generic;
using System.Reflection;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.ModelGeneration.Properties;

namespace nscreg.Utilities.ModelGeneration.PropertyCreators
{
    public class ReferencePropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return !(type.GetTypeInfo().IsGenericType && type.GetGenericTypeDefinition() == typeof(ICollection<>))
                && propInfo.IsDefined(typeof(ReferenceAttribute));
        }

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new ReferencePropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj),
                ((ReferenceAttribute) propInfo.GetCustomAttribute(typeof(ReferenceAttribute))).Lookup);
    }
}
