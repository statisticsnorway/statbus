using System;
using System.Reflection;

namespace nscreg.ModelGeneration
{
    /// <summary>
    /// Базовый класс создатель свойства
    /// </summary>
    public abstract class PropertyCreatorBase : IPropertyCreator
    {
        public abstract bool CanCreate(PropertyInfo propInfo);

        public abstract PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable);

        /// <summary>
        /// Метод получения атомарного значения
        /// </summary>
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

        /// <summary>
        /// Метод получения типа по умолчанию
        /// </summary>
        private static T Default<T>() => default(T);
    }
}
