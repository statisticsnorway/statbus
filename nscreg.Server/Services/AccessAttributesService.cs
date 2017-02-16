using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace nscreg.Server.Services
{
    public class AccessAttributesService
    {
        public IEnumerable<KeyValuePair<int, string>> GetAllSystemFunctions()
            => ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions)))
                .Select(x => new KeyValuePair<int, string>((int) x, x.ToString()));

        public IEnumerable<string> GetAllDataAttributes()
            =>
                typeof(StatisticalUnit).GetProperties().Select(x => x.Name);
    }
}