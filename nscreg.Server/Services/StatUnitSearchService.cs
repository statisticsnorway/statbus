using nscreg.Data;
using nscreg.ReadStack;
using nscreg.Server.Models.StatUnits;
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
            Predicate<string> checkClosure = superStr => superStr.Contains(query.Wildcard);
            var filteredIds = _readCtx.StatUnits
                .Where(x =>
                    (query.IncludeLiquidated || x.LiqDate == null)
                    && (string.IsNullOrEmpty(query.Wildcard)
                    || x.Name.Contains(query.Wildcard)
                    || checkClosure(x.Address.AddressPart1)
                    || checkClosure(x.Address.AddressPart2)
                    || checkClosure(x.Address.AddressPart3)
                    || checkClosure(x.Address.AddressPart4)
                    || checkClosure(x.Address.AddressPart5)
                    || checkClosure(x.Address.GeographicalCodes)))
                .Select(x => x.RegId);

            var resultGroup = filteredIds
                .Skip(query.PageSize * query.Page)
                .Take(query.PageSize)
                .GroupBy(p => new { Total = filteredIds.Count() })
                .FirstOrDefault();

            var total = resultGroup?.Key.Total ?? 0;
            var items = resultGroup != null
                ? StatUnitToObjectWithType(resultGroup, propNames)
                : Array.Empty<object>();

            return SearchVm.Create(
                items,
                total,
                (int)Math.Ceiling((double)total / query.PageSize));
        }

        private IEnumerable<object> StatUnitToObjectWithType(IEnumerable<int> statUnitIds, IEnumerable<string> propNames)
        {
            Func<string, Func<object, object>> serialize = type => unit => SearchItemVm.Create(unit, type, propNames);
            return _readCtx.LocalUnits.Where(lo => statUnitIds.Any(id => lo.RegId == id)).Select(serialize("localUnit"))
                .Concat(_readCtx.LegalUnits.Where(le => statUnitIds.Any(id => le.RegId == id)).Select(serialize("legalUnit")))
                    .Concat(_readCtx.EnterpriseUnits.Where(en => statUnitIds.Any(id => en.RegId == id)).Select(serialize("enterpriseUnit")));
        }
    }
}
