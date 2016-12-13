using Newtonsoft.Json;
using nscreg.Data;
using nscreg.ReadStack;
using nscreg.Server.Models.StatUnits;
using nscreg.Utilities;
using System;
using System.Collections.Generic;
using System.Linq;

namespace nscreg.Server.Services
{
    public class StatUnitSearchService
    {
        private readonly ReadContext _readCtx;

        public StatUnitSearchService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
        }

        public SearchVm Search(SearchQueryM query, IEnumerable<string> propNames)
        {
            Func<string, Func<string, bool>> checkSubstring = substr => str => str.Contains(substr);
            var checkSubstrClosure = checkSubstring(query.Wildcard);
            var filtered = _readCtx.StatUnits
                .Where(x =>
                    (query.IncludeLiquidated || x.LiqDate == null)
                        && x.Name.Contains(query.Wildcard)
                        || checkSubstrClosure(x.Address.AddressPart1)
                        || checkSubstrClosure(x.Address.AddressPart2)
                        || checkSubstrClosure(x.Address.AddressPart3)
                        || checkSubstrClosure(x.Address.AddressPart4)
                        || checkSubstrClosure(x.Address.AddressPart5)
                        || checkSubstrClosure(x.Address.GeographicalCodes));
            var resultGroup = filtered
                .Skip(query.PageSize * query.Page)
                .Take(query.PageSize)
                .GroupBy(p => new { Total = filtered.Count() })
                .FirstOrDefault();
            var serializedResult = resultGroup?
                .Select(x => JsonConvert.SerializeObject(x,
                    new JsonSerializerSettings { ContractResolver = new DynamicContractResolver(propNames) }))
                ?? Array.Empty<string>();
            return SearchVm.Create(
                serializedResult,
                resultGroup?.Key.Total ?? 0,
                (int)Math.Ceiling((double)(resultGroup?.Key.Total ?? 0) / query.PageSize));
        }
    }
}
