using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.ModelGeneration.Validation;
using nscreg.Utilities.Attributes;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    ///     Класс создатель свойства строки
    /// </summary>
    public class StringPropertyCreator : PropertyCreatorBase
    {
        public StringPropertyCreator(IValidationEndpointProvider validationEndpointProvider) : base(
            validationEndpointProvider)
        {
        }

        /// <summary>
        ///     Метод проверки создания свойства строки
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo)
        {
            return propInfo.PropertyType == typeof(string);
        }

        /// <summary>
        ///     Метод создатель свойства строки
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable,
            bool mandatory = false)
        {
            return new StringPropertyMetadata(
                propInfo.Name,
                mandatory,
                GetAtomicValue<string>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable,
                validationUrl: ValidationEndpointProvider.Get(propInfo.GetCustomAttribute<AsyncValidationAttribute>()
                    ?.ValidationType),
                popupLocalizedKey: propInfo.GetCustomAttribute<PopupLocalizedKeyAttribute>()?.PopupLocalizedKey);
        }
    }
}
