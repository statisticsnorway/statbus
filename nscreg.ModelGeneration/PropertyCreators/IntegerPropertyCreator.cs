using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class IntegerPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo)
            => !propInfo.IsDefined(typeof(ReferenceAttribute))
               && (propInfo.PropertyType == typeof(int) || propInfo.PropertyType == typeof(int?));

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new IntegerPropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj));
    }
}
