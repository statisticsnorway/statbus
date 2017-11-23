using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.ModelGeneration.PropertiesMetadata;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Класс создатель свойства деятельности
    /// </summary>
    public class ActivityPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return type.GetTypeInfo().IsGenericType
                   && type.GetGenericTypeDefinition() == typeof(IEnumerable<>)
                   && type.GenericTypeArguments[0] == typeof(Activity);
        }

        /// <summary>
        /// Метод создатель свойства деятельности
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
        {
            return new ActivityPropertyMetadata(
                propInfo.Name,
                true,
                obj == null ? Enumerable.Empty<Activity>() : (IEnumerable<Activity>) propInfo.GetValue(obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable
            );
        }
    }
}
