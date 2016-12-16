using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using nscreg.Utilities;
using System.Collections.Generic;

namespace nscreg.Server.Models.StatUnits
{
    public class SearchItemVm
    {
        public static object Create(object statUnit, int type, IEnumerable<string> propNames)
        {
            var jo = JObject.FromObject(
                statUnit,
                new JsonSerializer { ContractResolver = new DynamicContractResolver(propNames) });
            jo.Add("type", type);
            return jo.ToObject<object>();
        }
    }
}
