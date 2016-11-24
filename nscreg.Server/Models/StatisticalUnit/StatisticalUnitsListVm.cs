using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data;
using Newtonsoft.Json;

namespace nscreg.Server.Models.StatisticalUnit
{
    public class StatisticalUnitsListVm
    {
        public static StatisticalUnitsListVm Create(NSCRegDbContext db, int page, int pageSize, bool showAll)
        {
            IEnumerable<string> queriedUnits = db.LocalUnits.Select(JsonConvert.SerializeObject);
            queriedUnits.Concat(db.LegalUnits.Select(JsonConvert.SerializeObject));
            queriedUnits.Concat(db.EnterpriseUnits.Select(JsonConvert.SerializeObject));
            queriedUnits.Concat(db.EnterpriseGroups.Select(JsonConvert.SerializeObject));
            
            return new StatisticalUnitsListVm
            {
                Result = queriedUnits
                    .Skip(page * pageSize)
                    .Take(pageSize),
                TotalCount = queriedUnits.Count(),
                TotalPages = (int)Math.Ceiling((double)queriedUnits.Count() / pageSize)
            };
        }

        public IEnumerable<string> Result { get; set; }
        public int TotalCount { get; set; }
        public int TotalPages { get; set; }
    }
}
