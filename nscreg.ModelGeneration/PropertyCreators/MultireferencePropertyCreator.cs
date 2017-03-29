using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Attributes;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class MultireferencePropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return type.GetTypeInfo().IsGenericType
                   && type.GetGenericTypeDefinition() == typeof(ICollection<>)
                   && propInfo.IsDefined(typeof(ReferenceAttribute));
        }

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new MultiReferenceProperty(
                propInfo.Name,
                obj == null
                    ? Enumerable.Empty<int>()
                    : ((IEnumerable<object>) propInfo.GetValue(obj)).Select(
                        x => (int) x.GetType().GetProperty("RegId").GetValue(x)), // can't reference IStatUnit
                ((ReferenceAttribute) propInfo.GetCustomAttribute(typeof(ReferenceAttribute))).Lookup);
    }
}
