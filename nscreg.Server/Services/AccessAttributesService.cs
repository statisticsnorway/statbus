using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Collections.Generic;
using System.Reflection;

namespace nscreg.Server.Services
{
    public class AccessAttributesService
    {
        private readonly NSCRegDbContext _dbContext;

        public AccessAttributesService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public IEnumerable<KeyValuePair<int, string>> GetAllSystemFunctions()
        {
            var arr = new List<KeyValuePair<int, string>>();
            foreach (var item in Enum.GetValues(typeof(SystemFunction)))
                arr.Add(new KeyValuePair<int, string>((int)item, item.ToString()));
            return arr;
        }

        public IEnumerable<KeyValuePair<int, string>> GetAllDataAttributes()
        {
            var arr = new List<KeyValuePair<int, string>>();
            foreach (var prop in typeof(StatisticalUnit).GetProperties())
                arr.Add(new KeyValuePair<int, string>(arr.Count, prop.Name));
            return arr;
        }
    }
}
