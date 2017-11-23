using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Класс создатель свойства строки
    /// </summary>
    public class StringPropertyCreator : PropertyCreatorBase
    {
        /// <summary>
        /// Метод проверки создания свойства строки
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo) => propInfo.PropertyType == typeof(string);

        /// <summary>
        /// Метод создатель свойства строки
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
            => new StringPropertyMetadata(
                propInfo.Name,
                false,
                GetAtomicValue<string>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable);
    }
}
