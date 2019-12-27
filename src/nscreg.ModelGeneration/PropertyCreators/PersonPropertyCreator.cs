using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.ModelGeneration.PropertiesMetadata;
using nscreg.ModelGeneration.Validation;
using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration.PropertyCreators
{
    /// <summary>
    ///     Person Creator Class
    /// </summary>
    public class PersonPropertyCreator : PropertyCreatorBase
    {
        public PersonPropertyCreator(IValidationEndpointProvider validationEndpointProvider) : base(
            validationEndpointProvider)
        {
        }

        /// <summary>
        ///     Person Creation Verification Method
        /// </summary>
        public override bool CanCreate(PropertyInfo propInfo)
        {
            var type = propInfo.PropertyType;
            return type.GetTypeInfo().IsGenericType
                   && type.GetGenericTypeDefinition() == typeof(IEnumerable<>)
                   && type.GenericTypeArguments[0] == typeof(Person);
        }

        /// <summary>
        ///     Person Property Creator Method
        /// </summary>
        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj, bool writable,
            bool mandatory = false)
        {
            var persons = obj == null ? Enumerable.Empty<Person>() : (IEnumerable<Person>)propInfo.GetValue(obj);
            var regIdPropertyInfo = typeof(IStatisticalUnit).GetProperty(nameof(IStatisticalUnit.RegId));
            var regId = obj == null ? default(int) : (int) regIdPropertyInfo.GetValue(obj);
            persons.ForEach(x=>x.Role = x.PersonsUnits.FirstOrDefault(y=>y.UnitId == regId).PersonTypeId);

            return new PersonPropertyMetada(
                propInfo.Name,
                mandatory,
                persons,
                GetOpder(propInfo),
                propInfo.GetCustomAttribute<DisplayAttribute>()?.GroupName,
                writable: writable
            );
        }
    }
}
