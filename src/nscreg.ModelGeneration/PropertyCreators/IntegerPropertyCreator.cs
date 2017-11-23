using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Класс создатель свойства целого числа
    /// </summary>
    public class IntegerPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => !propInfo.IsDefined(typeof(ReferenceAttribute)) && !propInfo.IsDefined(typeof(SearchComponentAttribute))
               && (propInfo.PropertyType == typeof(int) || propInfo.PropertyType == typeof(int?));

        /// <summary>
        /// Метод создатель свойства целого числа
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
            => new IntegerPropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable);
    }
}
