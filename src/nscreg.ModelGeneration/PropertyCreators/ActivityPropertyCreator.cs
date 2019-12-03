using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.ModelGeneration.Validation;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    ///     Class Creator Activity Properties
    /// </summary>
    public class ActivityPropertyCreator : PropertyCreatorBase
    {
        public ActivityPropertyCreator(IValidationEndpointProvider validationEndpointProvider) : base(
            validationEndpointProvider)
        {
        }

        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return type.GetTypeInfo().IsGenericType
                   && type.GetGenericTypeDefinition() == typeof(IEnumerable<>)
                   && type.GenericTypeArguments[0] == typeof(Activity);
        }

        /// <summary>
        ///     Activity Creator Method
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable,
            bool mandatory = false)
        {
            return new ActivityPropertyMetadata(
                propInfo.Name,
                mandatory,
                obj == null ? Enumerable.Empty<Activity>() : (IEnumerable<Activity>) propInfo.GetValue(obj),
                GetOpder(propInfo),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable
            );
        }
    }
}
