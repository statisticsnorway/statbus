using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Collections.Generic;
using System.Reflection;

namespace nscreg.Server.Services
{
    public class AccessAttributesService
    {
        public IEnumerable<KeyValuePair<int, string>> GetAllSystemFunctions()
        {
            var arr = new List<KeyValuePair<int, string>>();
            foreach (var item in Enum.GetValues(typeof(SystemFunction)))
                arr.Add(new KeyValuePair<int, string>((int)item, item.ToString()));
            return arr;
        }

        public IEnumerable<string> GetAllDataAttributes()
        {
            var arr = new List<string>();
            foreach (var prop in typeof(StatisticalUnit).GetProperties())
                arr.Add(prop.Name);
            return arr;
        }
    }
}
