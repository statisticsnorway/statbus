using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.ModelGeneration.PropertiesMetadata
{
    /// <summary>
    /// Класс метаданные свойств персоны
    /// </summary>
    public class PersonPropertyMetada : PropertyMetadataBase
    {
        public PersonPropertyMetada(string name, bool isRequired, IEnumerable<Person> value, string groupName = null, string localizeKey = null)
            : base(name, isRequired, localizeKey, groupName)
        {
            Value = value;
        }

        public IEnumerable<Person> Value { get; set; }

        public override PropertyType Selector => PropertyType.Persons;
    }
}
