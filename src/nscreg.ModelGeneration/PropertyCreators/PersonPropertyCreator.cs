using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.ModelGeneration.PropertiesMetadata;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Класс создатель свойства персоны
    /// </summary>
    public class PersonPropertyCreator : PropertyCreatorBase
    {
        /// <summary>
        /// Метод проверки создания персоны
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return type.GetTypeInfo().IsGenericType
                   && type.GetGenericTypeDefinition() == typeof(IEnumerable<>)
                   && type.GenericTypeArguments[0] == typeof(Person);
        }

        /// <summary>
        /// Метод создатель свойства персоны
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
        {
            return new PersonPropertyMetada(
                propInfo.Name,
                true,
                obj == null ? Enumerable.Empty<Person>() : (IEnumerable<Person>)propInfo.GetValue(obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable
            );
        }
    }
}
