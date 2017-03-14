using System;
using System.Reflection;

namespace nscreg.Utilities.ModelGeneration
{
    public abstract class PropertyCreatorBase : IPropertyCreator
    {
        public abstract bool CanCreate(PropertyInfo propInfo);

        public abstract PropertyMetadataBase Create(PropertyInfo propInfo, object obj);

        protected T GetAtomicValue<T>(PropertyInfo propInfo, object obj)
            => (T) (obj == null
                ? GetType()
                    .GetMethod(nameof(Default))
                    .MakeGenericMethod(
                        propInfo.PropertyType.GetTypeInfo().IsGenericType
                        && propInfo.PropertyType.GetGenericTypeDefinition() == typeof(Nullable<>)
                            ? Nullable.GetUnderlyingType(propInfo.PropertyType)
                            : propInfo.PropertyType)
                    .Invoke(null, null)
                : (T) propInfo.GetValue(obj));

        private static T Default<T>() => default(T);
    }
}
