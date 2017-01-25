using System.Reflection;
using nscreg.Server.Models.Dynamic.Property;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    public class StringPropertyCreator : PropertyCreatorBase
    {
        public override bool CanCreate(PropertyInfo propertyInfo)
        {
            return propertyInfo.PropertyType == typeof(string);
        }

        public override PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj)
        {
            return new StringPropertyMetadata(propertyInfo.Name, false, GetAtomicValue<string>(propertyInfo, obj));
        }
    }
}