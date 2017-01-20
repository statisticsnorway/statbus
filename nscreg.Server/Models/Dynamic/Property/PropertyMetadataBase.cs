using nscreg.Utilities;
using Newtonsoft.Json;

namespace nscreg.Server.Models.Dynamic.Property
{
    public abstract class PropertyMetadataBase
    {
        protected PropertyMetadataBase(string name, bool isRequired)
        {
            Name = name.LowerFirstLetter();
            IsRequired = isRequired;
        }

        public string Name { get; set; }
        public bool IsRequired { get; set; }
        public abstract PropertyType Selector { get; }

        public enum PropertyType
        {
            Boolean,
            DateTime,
            Float,
            Integer,
            MultiReference,
            Reference,
            String
        }
    }
}