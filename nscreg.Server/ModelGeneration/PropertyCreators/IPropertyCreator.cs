using System.Reflection;
using nscreg.Server.Models.Dynamic.Property;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    public interface IPropertyCreator
    {
        bool CanCreate(PropertyInfo propertyInfo);
        PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj);
    }
}