using Newtonsoft.Json.Serialization;
using System.Collections.Generic;
using Newtonsoft.Json;
using System;
using System.Linq;

namespace nscreg.Utilities
{
    public class DynamicContractResolver : CamelCasePropertyNamesContractResolver
    {
        private readonly IEnumerable<string> _propNames;

        /// <summary>
        /// List of allowed property names
        /// </summary>
        /// <param name="propNames"></param>
        public DynamicContractResolver(IEnumerable<string> propNames)
        {
            _propNames = propNames.Select(x => x.LowerFirstLetter());
        }

        protected override IList<JsonProperty> CreateProperties(Type type, MemberSerialization memberSerialization)
            => base.CreateProperties(type, memberSerialization)
            .Where(p => _propNames.Contains(p.PropertyName))
            .ToList();
    }
}
