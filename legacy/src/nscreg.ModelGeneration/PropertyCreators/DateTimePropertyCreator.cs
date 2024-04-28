using System;
using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.ModelGeneration.Validation;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    ///     Date Creator Class
    /// </summary>
    public class DateTimeOffsetPropertyCreator : PropertyCreatorBase
    {
        public DateTimeOffsetPropertyCreator(IValidationEndpointProvider validationEndpointProvider) : base(
            validationEndpointProvider)
        {
        }

        public override bool CanCreate(PropertyInfo propInfo)
        {
            return propInfo.PropertyType == typeof(DateTimeOffset) || propInfo.PropertyType == typeof(DateTimeOffset?);
        }

        /// <summary>
        ///     Method Creator Date Properties
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable,
            bool mandatory = false)
        {
            var propertyMetadata = new DateTimeOffsetPropertyMetadata(
                propInfo.Name,
                mandatory || !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<DateTimeOffset?>(propInfo, obj),
                GetOpder(propInfo),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable,
                popupLocalizedKey: propInfo.GetCustomAttribute<PopupLocalizedKeyAttribute>()?.PopupLocalizedKey);
            return propertyMetadata;
        }
    }
}
