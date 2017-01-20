using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Server.ModelGeneration.PropertyCreators;
using nscreg.Server.Models.Dynamic.Property;

namespace nscreg.Server.ModelGeneration.ModelCreators
{
    public static class PropertyMetadataFactory
    {
        private static readonly List<IPropertyCreator> PropertyCreators;

        static PropertyMetadataFactory()
        {
            PropertyCreators = typeof(PropertyMetadataFactory).GetTypeInfo().Assembly.GetTypes()
                .Where(x => !x.GetTypeInfo().IsAbstract && typeof(IPropertyCreator).IsAssignableFrom(x))
                .Select(Activator.CreateInstance).Cast<IPropertyCreator>().ToList();
        }

        public static PropertyMetadataBase Create(PropertyInfo propertyInfo, object obj)
        {
            var creator = PropertyCreators.FirstOrDefault(x => x.CanCreate(propertyInfo));
            return creator?.Create(propertyInfo, obj);
        }
    }
}