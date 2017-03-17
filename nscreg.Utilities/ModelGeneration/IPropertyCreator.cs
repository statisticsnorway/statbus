using System.Reflection;

namespace nscreg.Utilities.ModelGeneration
{
    public interface IPropertyCreator
    {
        bool CanCreate(PropertyInfo propInfo);

        PropertyMetadataBase Create(PropertyInfo propInfo, object obj);
    }
}
