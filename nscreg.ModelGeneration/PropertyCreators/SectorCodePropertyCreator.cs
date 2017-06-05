using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.ModelGeneration.PropertiesMetadata;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class SectorCodePropertyCreator : IPropertyCreator
    {
        public bool CanCreate(PropertyInfo propInfo)
        {
            return propInfo.PropertyType == typeof(SectorCode);
        }

        public PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
        {
            return new SectorCodePropertyMetadata(
                propInfo.Name,
                true,
                obj == null ? new SectorCode() : (SectorCode)propInfo.GetValue(obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName
            );
        }
    }
}
