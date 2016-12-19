using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using nscreg.Utilities;
using System.Collections.Generic;
using nscreg.Data.Constants;

namespace nscreg.Server.Models.StatUnits
{
    // ReSharper disable once ClassNeverInstantiated.Global
    public class SearchItemVm
    {
        public static object Create(object statUnit, StatUnitTypes type, IEnumerable<string> propNames)
        {
            var jo = JObject.FromObject(
                statUnit,
                new JsonSerializer {ContractResolver = new DynamicContractResolver(propNames)});
            jo.Add("type", (int) type);
            return jo.ToObject<object>();
        }
    }
}
