using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Класс создатель свойства ссылки
    /// </summary>
    public class ReferencePropertyCreator : PropertyCreatorBase
    {
        /// <summary>
        /// Метод проверки создания свойства ссылки
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return !(type.GetTypeInfo().IsGenericType && type.GetGenericTypeDefinition() == typeof(ICollection<>))
                   && propInfo.IsDefined(typeof(ReferenceAttribute));
        }

        /// <summary>
        /// Метод создатель свойства ссылки
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
            => new ReferencePropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj),
                ((ReferenceAttribute) propInfo.GetCustomAttribute(typeof(ReferenceAttribute))).Lookup,
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable);
    }
}
