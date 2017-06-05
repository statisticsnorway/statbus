using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.ModelGeneration.PropertiesMetadata;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class LegalFormPropertyCreator : IPropertyCreator
    {
        public bool CanCreate(PropertyInfo propInfo)
        {
            return propInfo.PropertyType == typeof(LegalForm);
        }

        public PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
        {
            return new LegalFormPropertyMetadata(
                propInfo.Name,
                true,
                obj == null ? new LegalForm() : (LegalForm)propInfo.GetValue(obj),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName
            );
        }
    }
}
