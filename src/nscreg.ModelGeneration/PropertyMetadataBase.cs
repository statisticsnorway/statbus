using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration
{
    /// <summary>
    /// Базовый класс метаданные свойства
    /// </summary>
    public abstract class PropertyMetadataBase
    {
        protected PropertyMetadataBase(string name, bool isRequired, string localizeKey = null, string groupName = null, bool writable = false)
        {
            LocalizeKey = localizeKey ?? name;
            Name = name.LowerFirstLetter();
            IsRequired = isRequired;
            GroupName = groupName;
            Writable = writable;
        }

        public string Name { get; set; }

        public bool IsRequired { get; set; }

        public abstract PropertyType Selector { get; }

        public string LocalizeKey { get; set; }
        public string GroupName { get; set; }
        public bool Writable { get; set; }

        public enum PropertyType
        {
            Boolean = 0,
            DateTime,
            Float,
            Integer,
            MultiReference,
            Reference,
            String,
            Activities,
            Addresses,
            Persons,
            SearchComponent,
            Countries,
        }
    }
}
