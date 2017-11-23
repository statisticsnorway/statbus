using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.ModelGeneration.PropertiesMetadata;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Person property creator
    /// </summary>
    public class CountryPropertyCreator : PropertyCreatorBase
    {
        /// <summary>
        /// Check can create method
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return type.GetTypeInfo().IsGenericType
                   && type.GetGenericTypeDefinition() == typeof(IEnumerable<>)
                   && type.GenericTypeArguments[0] == typeof(Country);
        }

        /// <summary>
        /// Creator of property method
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
        {
            return new CountryPropertyMetadata(
                propInfo.Name,
                true,
                obj == null ? Enumerable.Empty<Country>() : (IEnumerable<Country>)propInfo.GetValue(obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable
            );
        }
    }
}
