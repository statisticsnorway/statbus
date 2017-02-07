using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Server.Models.Dynamic.Property;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    public class MultireferencePropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propertyInfo)
        {
            var type = propertyInfo.PropertyType;
            return
                type.GetTypeInfo().IsGenericType && type.GetGenericTypeDefinition() == typeof(ICollection<>) &&
                propertyInfo.IsDefined(typeof(ReferenceAttribute));
        }

        public override PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj)
        {
            var value = obj == null ? Enumerable.Empty<IStatisticalUnit>() : propertyInfo.GetValue(obj);
            var lookup = ((ReferenceAttribute) propertyInfo.GetCustomAttribute(typeof(ReferenceAttribute))).Lookup;
            var ids = ((IEnumerable) value).Cast<IStatisticalUnit>().Select(x => x.RegId);
            return new MultiReferencePropery(propertyInfo.Name, ids, lookup);
        }
    }
}