using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Common.Models.DataAccess;

namespace nscreg.Server.Common.Services
{
    public class AccessAttributesService
    {
        public AccessAttributesService(NSCRegDbContext context)
        {
            DbContext = context;
            ReadCtx = new ReadContext(context);
        }

        private ReadContext ReadCtx { get; }

        private NSCRegDbContext DbContext { get; }

        public IEnumerable<KeyValuePair<int, string>> GetAllSystemFunctions()
            => ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions)))
                .Select(x => new KeyValuePair<int, string>((int) x, x.ToString()));

        public DataAccessModel GetAllDataAccessAttributes()
        {
            return DataAccessModel.FromString(null);
        }
    }
}