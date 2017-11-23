using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Класс создатель свойства булева
    /// </summary>
    public class BooleanPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => propInfo.PropertyType == typeof(bool) || propInfo.PropertyType == typeof(bool?);

        /// <summary>
        /// Метод создатель свойства булева
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
            => new BooleanPropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<bool?>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable);
    }
}
