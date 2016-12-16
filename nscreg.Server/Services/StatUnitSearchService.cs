using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
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
            var filtered = _readCtx.StatUnits.Where(x => (query.IncludeLiquidated || x.LiqDate == null));

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                Predicate<string> checkWildcard = superStr => !string.IsNullOrEmpty(superStr) && superStr.Contains(query.Wildcard);
                filtered = filtered.Where(x =>
                    x.Name.Contains(query.Wildcard)
                    || checkWildcard(x.Address.AddressPart1)
                    || checkWildcard(x.Address.AddressPart2)
                    || checkWildcard(x.Address.AddressPart3)
                    || checkWildcard(x.Address.AddressPart4)
                    || checkWildcard(x.Address.AddressPart5)
                    || checkWildcard(x.Address.GeographicalCodes));
            }

            if (query.Type.HasValue)
            {
                Func<StatisticalUnit, bool> checkType = GetCheckTypeClosure(query.Type.Value);
                filtered = filtered.Where(x => checkType(x));
            }

            if (query.TurnoverFrom.HasValue)
                filtered = filtered.Where(x => x.Turnover > query.TurnoverFrom);

            if (query.TurnoverTo.HasValue)
                filtered = filtered.Where(x => x.Turnover < query.TurnoverTo);

            var ids = filtered.Select(x => x.RegId);

            var resultGroup = ids
                .Skip(query.PageSize * query.Page)
                .Take(query.PageSize)
                .GroupBy(p => new { Total = ids.Count() })
                .FirstOrDefault();

            var total = resultGroup?.Key.Total ?? 0;

            return SearchVm.Create(
                resultGroup != null
                    ? StatUnitsToObjectsWithType(resultGroup, propNames)
                    : Array.Empty<object>(),
                total,
                (int)Math.Ceiling((double)total / query.PageSize));
        }

        private IEnumerable<object> StatUnitsToObjectsWithType(IEnumerable<int> statUnitIds, IEnumerable<string> propNames)
        {
            Func<int, Func<object, object>> serialize = type => unit => SearchItemVm.Create(unit, type, propNames);
            return _readCtx.LocalUnits.Where(lo => statUnitIds.Any(id => lo.RegId == id)).Select(serialize((int)StatUnitTypes.LocalUnit))
                .Concat(_readCtx.LegalUnits.Where(le => statUnitIds.Any(id => le.RegId == id)).Select(serialize((int)StatUnitTypes.LegalUnit)))
                    .Concat(_readCtx.EnterpriseUnits.Where(en => statUnitIds.Any(id => en.RegId == id)).Select(serialize((int)StatUnitTypes.EnterpriseUnit)));
        }

        private Func<StatisticalUnit, bool> GetCheckTypeClosure(StatUnitTypes type)
        {
            switch (type)
            {
                case StatUnitTypes.LegalUnit:
                    return x => x is LegalUnit;
                case StatUnitTypes.LocalUnit:
                    return x => x is LocalUnit;
                case StatUnitTypes.EnterpriseUnit:
                    return x => x is EnterpriseUnit;
                case StatUnitTypes.EnterpriseGroup:
                    throw new NotImplementedException("enterprise group is not supported yet");
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), "unknown statUnit type");
            }
        }
    }
}
