using nscreg.Server.Models.Dynamic.Property;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;

namespace nscreg.Server.Models.Infrastructure
{
    public class ViewModelBase
    {
        public PropertyMetadataBase[] Properties { get; set; } = {};
    }
}