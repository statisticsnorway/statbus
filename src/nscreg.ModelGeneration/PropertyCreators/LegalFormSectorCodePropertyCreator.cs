using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.ModelGeneration.Validation;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    ///    Class creator property sector code of legal ownership
    /// </summary>
    public class LegalFormSectorCodePropertyCreator : PropertyCreatorBase
    {
        public LegalFormSectorCodePropertyCreator(IValidationEndpointProvider validationEndpointProvider) : base(
            validationEndpointProvider)
        {
        }

        /// <summary>
        ///     Method for checking on the creation of a property of a sector of a code of a legal form of ownership
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo)
        {
            return propInfo.IsDefined(typeof(SearchComponentAttribute));
        }

        /// <summary>
        ///     Method creator property sector code legal form of ownership
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable,
            bool mandatory = false)
        {
            return new LegalFormSectorCodePropertyMetadata(
                propInfo.Name,
                mandatory || !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj),
                GetOpder(propInfo),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable,
                popupLocalizedKey: propInfo.GetCustomAttribute<PopupLocalizedKeyAttribute>()?.PopupLocalizedKey);
        }
    }
}
