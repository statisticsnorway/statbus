using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.ModelGeneration.PropertiesMetadata;

namespace nscreg.ModelGeneration.PropertyCreators
{
    public class AddressPropertyCreator : IPropertyCreator
    {
        public bool CanCreate(PropertyInfo propInfo)
        {
            return propInfo.PropertyType == typeof(Address);
        }

        public PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
        {
            return new AddressPropertyMetadata(
               propInfo.Name,
               true,
               obj == null ? new Address() : (Address)propInfo.GetValue(obj),
               propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName
           );
        }
    }
}
