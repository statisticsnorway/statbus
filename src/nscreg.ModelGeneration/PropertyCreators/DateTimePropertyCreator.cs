using System;
using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class DateTimePropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => propInfo.PropertyType == typeof(DateTime) || propInfo.PropertyType == typeof(DateTime?);

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new DateTimePropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<DateTime?>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName);
    }
}
