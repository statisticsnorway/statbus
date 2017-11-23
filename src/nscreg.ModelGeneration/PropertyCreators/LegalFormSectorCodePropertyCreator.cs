using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    /// Класс создатель свойства сектора кода правовой формы собственности
    /// </summary>
    public class LegalFormSectorCodePropertyCreator : PropertyCreatorBase
    {
        /// <summary>
        /// Метод проверки на создание свойства сектора кода правовой формы собственности
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo) => propInfo.IsDefined(typeof(SearchComponentAttribute));

        /// <summary>
        /// Метод создатель свойства сектора кода правовой формы собственности
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable)
            => new LegalFormSectorCodePropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable);
    }
}
