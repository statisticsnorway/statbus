using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Класс создатель свойства числа с плавающей точкой
    /// </summary>
    public class FloatPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => propInfo.PropertyType == typeof(decimal) || propInfo.PropertyType == typeof(decimal?);

        /// <summary>
        /// Метод создатель свойства числа с плавающей точкой
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
            => new FloatPropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<decimal?>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable);
    }
}
