using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace nscreg.ReadStack
{
    public class ReadContext
    {
        private readonly NSCRegDbContext _dbContext;

        public ReadContext(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public IQueryable<KeyValuePair<int, string>> SystemFunctions
        {
            get
            {
                var arr = new List<KeyValuePair<int, string>>();
                foreach (var item in Enum.GetValues(typeof(SystemFunction)))
                    arr.Add(new KeyValuePair<int, string>((int)item, item.ToString()));
                return arr.AsQueryable();
            }
        }

        public IQueryable<string> StatUnitAttributes
        {
            get
            {
                var arr = new List<string>();
                foreach (var prop in typeof(StatisticalUnit).GetProperties())
                    arr.Add(prop.Name);
                return arr.AsQueryable();
            }
        }

        public IQueryable<Role> Roles { get { return _dbContext.Roles; } }

        public IQueryable<User> Users {  get { return _dbContext.Users; } }
    }
}
