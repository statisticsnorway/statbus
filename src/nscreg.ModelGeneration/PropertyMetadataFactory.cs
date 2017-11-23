using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace nscreg.ModelGeneration
{
    /// <summary>
    /// Класс фабрика свойств метаданных
    /// </summary>
    public static class PropertyMetadataFactory
    {
        private static readonly IEnumerable<IPropertyCreator> PropertyCreators;

        static PropertyMetadataFactory()
        {
            PropertyCreators = typeof(PropertyMetadataFactory).GetTypeInfo().Assembly.GetTypes()
                .Where(x => !x.GetTypeInfo().IsAbstract && typeof(IPropertyCreator).IsAssignableFrom(x))
                .Select(Activator.CreateInstance)
                .Cast<IPropertyCreator>();
        }

        /// <summary>
        /// Метод фабрика свойств метаданных
        /// </summary>
        public static PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj, bool writable)
        {
            var creator = PropertyCreators.FirstOrDefault(x => x.CanCreate(propertyInfo));
            if (creator == null)
                throw new ArgumentException(
                    $"can't create property metadata for property {propertyInfo.Name} of type {propertyInfo.PropertyType}");
            return creator.Create(propertyInfo, obj, writable);
        }
    }
}
