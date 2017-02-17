using System.Reflection;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.ModelGeneration.Properties;

namespace nscreg.Utilities.ModelGeneration.PropertyCreators
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
