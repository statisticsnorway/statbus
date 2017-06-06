using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class LegalFormSectorCodePropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propInfo) => propInfo.IsDefined(typeof(SearchComponentAttribute));

        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
            => new LegalFormSectorCodePropertyMetadata(
                propInfo.Name,
                !propInfo.PropertyType.IsNullable(),
                GetAtomicValue<int?>(propInfo, obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName);
    }
}
