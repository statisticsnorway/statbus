using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.ModelGeneration.Validation;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    ///     Link Creator Class
    /// </summary>
    public class ReferencePropertyCreator : PropertyCreatorBase
    {
        public ReferencePropertyCreator(IValidationEndpointProvider validationEndpointProvider) : base(
            validationEndpointProvider)
        {
        }

        /// <summary>
        ///     Verification Method for Link Property Creation
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return !(type.GetTypeInfo().IsGenericType && type.GetGenericTypeDefinition() == typeof(ICollection<>))
                   && propInfo.IsDefined(typeof(ReferenceAttribute));
        }

        /// <summary>
        ///     Link Property Creator Method
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable,
            bool mandatory = false)
        {
            return new ReferencePropertyMetadata(
                propInfo.Name,
                mandatory || !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj),
                ((ReferenceAttribute) propInfo.GetCustomAttribute(typeof(ReferenceAttribute))).Lookup,
                GetOpder(propInfo),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable,
                popupLocalizedKey: propInfo.GetCustomAttribute<PopupLocalizedKeyAttribute>()?.PopupLocalizedKey);
        }
    }
}
