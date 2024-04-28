using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.ModelGeneration.Validation;
using nscreg.Utilities.Attributes;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    ///     Class creator of string property
    /// </summary>
    public class StringPropertyCreator : PropertyCreatorBase
    {
        public StringPropertyCreator(IValidationEndpointProvider validationEndpointProvider) : base(
            validationEndpointProvider)
        {
        }

        /// <summary>
        ///     Verification Method for Creating a String Property
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo)
        {
            return propInfo.PropertyType == typeof(string);
        }

        /// <summary>
        ///     String Property Creator Method
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable,
            bool mandatory = false)
        {
            return new StringPropertyMetadata(
                propInfo.Name,
                mandatory,
                GetAtomicValue<string>(propInfo, obj),
                GetOpder(propInfo),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable,
                validationUrl: ValidationEndpointProvider.Get(propInfo.GetCustomAttribute<AsyncValidationAttribute>()
                    ?.ValidationType),
                popupLocalizedKey: propInfo.GetCustomAttribute<PopupLocalizedKeyAttribute>()?.PopupLocalizedKey);
        }
    }
}
