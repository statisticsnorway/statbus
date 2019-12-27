using System;
using System.ComponentModel.DataAnnotations;
using System.Reflection;
using nscreg.ModelGeneration.Validation;

namespace nscreg.ModelGeneration
{
    /// <summary>
    /// Base class property creator
    /// </summary>
    public abstract class PropertyCreatorBase : IPropertyCreator
    {
        protected IValidationEndpointProvider ValidationEndpointProvider { get; }

        protected PropertyCreatorBase(IValidationEndpointProvider validationEndpointProvider)
        {
            ValidationEndpointProvider = validationEndpointProvider;
        }

        public abstract bool CanCreate(PropertyInfo propInfo);

        public abstract PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable, bool mandatory = false);

        /// <summary>
        /// Method for obtaining atomic value
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

        protected int GetOpder(PropertyInfo propInfo) =>
            propInfo.GetCustomAttribute<DisplayAttribute>()?.Order ?? int.MaxValue;

        /// <summary>
        /// Default Type Method
        /// </summary>
        private static T Default<T>() => default(T);
    }
}
