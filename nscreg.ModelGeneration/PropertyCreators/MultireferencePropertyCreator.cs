using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
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
                   && type.GetGenericTypeDefinition() == typeof(ICollection<>) && typeof(IStatisticalUnit).IsAssignableFrom(type.GetGenericArguments()[0])
                   && propInfo.IsDefined(typeof(ReferenceAttribute));
        }

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
        {
            return new MultiReferenceProperty(
                propInfo.Name,
                obj == null
                    ? Enumerable.Empty<int>()
                    : ((IEnumerable<object>) propInfo.GetValue(obj)).Cast<IStatisticalUnit>().Where(v => !v.IsDeleted && v.ParrentId == null).Select(x => x.RegId),
                ((ReferenceAttribute) propInfo.GetCustomAttribute(typeof(ReferenceAttribute))).Lookup,
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName);
        }
    }
}
