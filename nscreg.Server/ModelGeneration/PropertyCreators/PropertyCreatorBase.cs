using System.Reflection;
using nscreg.Server.Models.Dynamic.Property;

namespace nscreg.Server.ModelGeneration.PropertyCreators
{
    public abstract class PropertyCreatorBase : IPropertyCreator
    {
        public abstract bool CanCreate(PropertyInfo propertyInfo);


        public abstract PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj);

        protected T GetAtomicValue<T>(PropertyInfo propertyInfo, object obj)
            =>
                (T)
                (obj == null
                    ? GetType()
                        .GetMethod(nameof(Default))
                        .MakeGenericMethod(propertyInfo.PropertyType)
                        .Invoke(null, null)
                    : (T) propertyInfo.GetValue(obj));

        private T Default<T>() => default(T);
    }
}