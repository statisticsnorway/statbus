using Newtonsoft.Json.Serialization;
using System.Collections.Generic;
using Newtonsoft.Json;
using System;
using System.Linq;

namespace nscreg.Utilities
{
    public class DynamicContractResolver : CamelCasePropertyNamesContractResolver
    {
        private readonly Type _type;
        private readonly IEnumerable<string> _allowedPropNames;

        /// <summary>
        /// List of allowed property names
        /// </summary>
        /// <param name="type"></param>
        /// <param name="propNames"></param>
        public DynamicContractResolver(Type type, IEnumerable<string> propNames)
        {
            _type = type;
            _allowedPropNames = propNames.Select(x => x.LowerFirstLetter()).ToList();
        }

        protected override IList<JsonProperty> CreateProperties(Type type, MemberSerialization memberSerialization)
        {
            var jsonProperties = base.CreateProperties(type, memberSerialization);
            if (_type != type) return jsonProperties;
            var result = new List<JsonProperty>();
            foreach (var jsonProperty in jsonProperties)
                if (_allowedPropNames.Contains(jsonProperty.PropertyName))
                    result.Add(jsonProperty);
            return result;
        }
    }
}
