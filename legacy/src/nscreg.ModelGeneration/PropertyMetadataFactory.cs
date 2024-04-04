using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.ModelGeneration.Validation;

namespace nscreg.ModelGeneration
{
    /// <summary>
    /// Metadata Property Factory Class
    /// </summary>
    public static class PropertyMetadataFactory
    {
        private static readonly IEnumerable<IPropertyCreator> PropertyCreators;

        static PropertyMetadataFactory()
        {
            PropertyCreators = typeof(PropertyMetadataFactory).GetTypeInfo().Assembly.GetTypes()
                .Where(x => !x.GetTypeInfo().IsAbstract && typeof(IPropertyCreator).IsAssignableFrom(x))
                .Select(x => Activator.CreateInstance(x, new ValidationEndpointProvider()))
                .Cast<IPropertyCreator>();
        }

        /// <summary>
        /// Method Factory Metadata Properties
        /// </summary>
        public static PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj, bool writable, bool? mandatory)
        {
            var creator = PropertyCreators.FirstOrDefault(x => x.CanCreate(propertyInfo));
            if (creator == null)
                throw new ArgumentException(
                    $"can't create property metadata for property {propertyInfo.Name} of type {propertyInfo.PropertyType}");
            return mandatory.HasValue
                ? creator.Create(propertyInfo, obj, writable, mandatory.Value)
                : creator.Create(propertyInfo, obj, writable);
        }
    }
}
