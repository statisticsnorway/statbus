using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.ModelGeneration.Validation;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    ///     Class creator of an integer property
    /// </summary>
    public class IntegerPropertyCreator : PropertyCreatorBase
    {
        public IntegerPropertyCreator(IValidationEndpointProvider validationEndpointProvider) : base(
            validationEndpointProvider)
        {
        }

        public override bool CanCreate(PropertyInfo propInfo)
        {
            return !propInfo.IsDefined(typeof(ReferenceAttribute)) &&
                   !propInfo.IsDefined(typeof(SearchComponentAttribute))
                   && (propInfo.PropertyType == typeof(int) || propInfo.PropertyType == typeof(int?));
        }

        /// <summary>
        ///     Method creator of an integer property
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable, bool mandatory)
        {
            return new IntegerPropertyMetadata(
                propInfo.Name,
                mandatory || !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj),
                GetOpder(propInfo),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable,
                popupLocalizedKey:propInfo.GetCustomAttribute<PopupLocalizedKeyAttribute>()?.PopupLocalizedKey);
        }
    }
}
