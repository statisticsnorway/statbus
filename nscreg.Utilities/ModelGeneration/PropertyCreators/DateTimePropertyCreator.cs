using System;
using System.Reflection;
using nscreg.Utilities.ModelGeneration.PropertiesMetadata;

namespace nscreg.Utilities.ModelGeneration.PropertyCreators
{
    public class DateTimePropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => propInfo.PropertyType == typeof(DateTime) || propInfo.PropertyType == typeof(DateTime?);

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new DateTimePropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<DateTime?>(propInfo, obj));
    }
}
