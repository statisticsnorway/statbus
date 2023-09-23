using nscreg.Utilities.Extensions;

namespace nscreg.ModelGeneration
{
    /// <summary>
    /// Base class property metadata
    /// </summary>
    public abstract class PropertyMetadataBase
    {
        protected PropertyMetadataBase(string name, bool isRequired, int order, string localizeKey = null, string groupName = null, bool writable = false, string validationUrl = null, string popupLocalizedKey = null)
        {
            LocalizeKey = localizeKey ?? name;
            Name = name.LowerFirstLetter();
            IsRequired = isRequired;
            GroupName = groupName;
            Writable = writable;
            ValidationUrl = validationUrl;
            PopupLocalizedKey = popupLocalizedKey;
            Order = order;
        }

        public string Name { get; set; }

        public bool IsRequired { get; set; }

        public abstract PropertyType Selector { get; }

        public string LocalizeKey { get; set; }
        public string GroupName { get; set; }
        public bool Writable { get; set; }
        public string ValidationUrl { get; set; }
        public string PopupLocalizedKey { get; set; }
        public int Order { get; set; }

        public enum PropertyType
        {
            Boolean = 0,
            DateTimeOffset,
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
