using System;
using System.Reflection;
using nscreg.Server.Models.Dynamic.Property;
using nscreg.Utilities;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    internal class DateTimePropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propertyInfo)
        {
            return propertyInfo.PropertyType == typeof(DateTime) || propertyInfo.PropertyType == typeof(DateTime?);
        }

        public override PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj)
        {
            return new DateTimePropertyMetadata(propertyInfo.Name, !propertyInfo.PropertyType.IsNullable(),
                GetAtomicValue<DateTime?>(propertyInfo, obj));
        }
    }
}