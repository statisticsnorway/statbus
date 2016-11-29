using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data;
using Newtonsoft.Json;
using nscreg.Data.Entities;

namespace nscreg.Server.Models.StatisticalUnit
{
    public class StatisticalUnitsListVm
    {
        public static StatisticalUnitsListVm Create(NSCRegDbContext db, int page, int pageSize, bool showAll)
        {
            var localUnits = db.LocalUnits.Where(x => x.IsDeleted == false);
            var legalUnits = db.LegalUnits.Where(x => x.IsDeleted == false);
            var entUUnits = db.EnterpriseUnits.Where(x => x.IsDeleted == false);
            var entGUnits = db.EnterpriseGroups.Where(x => x.IsDeleted == false);

            IEnumerable<string> queriedUnits = localUnits.Select(JsonConvert.SerializeObject)
                .Concat(legalUnits.Select(JsonConvert.SerializeObject))
                .Concat(entUUnits.Select(JsonConvert.SerializeObject))
                .Concat(entGUnits.Select(JsonConvert.SerializeObject));

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
