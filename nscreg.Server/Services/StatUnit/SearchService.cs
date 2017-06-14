using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Models.StatUnits;
using static nscreg.Server.Services.StatUnit.Common;

namespace nscreg.Server.Services.StatUnit
{
    public class SearchService
    {
        private readonly ReadContext _readCtx;
        private readonly UserService _userService;

        public SearchService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
            _userService = new UserService(dbContext);
        }

        public async Task<SearchVm> Search(SearchQueryM query, string userId, bool deletedOnly = false)
        {
            var propNames = await _userService.GetDataAccessAttributes(userId, null);
            var unit =
                _readCtx.StatUnits
                    .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                    .Include(x => x.Address)
                    .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                    .Select(
                        x =>
                            new
                            {
                                x.RegId,
                                x.Name,
                                x.Address,
                                x.Turnover,
                                x.Employees,
                                UnitType =
                                x is LocalUnit
                                    ? StatUnitTypes.LocalUnit
                                    : x is LegalUnit
                                        ? StatUnitTypes.LegalUnit
                                        : StatUnitTypes.EnterpriseUnit
                            });
            var group =
                _readCtx.EnterpriseGroups
                    .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                    .Include(x => x.Address)
                    .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                    .Select(
                        x =>
                            new
                            {
                                x.RegId,
                                x.Name,
                                x.Address,
                                x.Turnover,
                                x.Employees,
                                UnitType = StatUnitTypes.EnterpriseGroup
                            });
            var filtered = unit.Concat(group);

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                Predicate<string> checkWildcard =
                    superStr => !string.IsNullOrEmpty(superStr) && superStr.Contains(query.Wildcard);
                filtered = filtered.Where(x =>
                    x.Name.Contains(query.Wildcard)
                    || x.Address != null
                    && (checkWildcard(x.Address.AddressPart1)
                        || checkWildcard(x.Address.AddressPart2)
                        || checkWildcard(x.Address.AddressPart3)
                        || checkWildcard(x.Address.AddressPart4)
                        || checkWildcard(x.Address.AddressPart5)
                        || checkWildcard(x.Address.GeographicalCodes)));
            }

            if (query.Type.HasValue)
                filtered = filtered.Where(x => x.UnitType == query.Type.Value);

            if (query.TurnoverFrom.HasValue)
                filtered = filtered.Where(x => x.Turnover >= query.TurnoverFrom);

            if (query.TurnoverTo.HasValue)
                filtered = filtered.Where(x => x.Turnover <= query.TurnoverTo);

            if (query.EmployeesNumberFrom.HasValue)
                filtered = filtered.Where(x => x.Employees >= query.EmployeesNumberFrom);

            if (query.EmployeesNumberTo.HasValue)
                filtered = filtered.Where(x => x.Employees <= query.EmployeesNumberTo);

            var total = filtered.Count();
            var take = query.PageSize;
            var skip = query.PageSize * (query.Page - 1);

            var result = filtered
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(query.PageSize)
                .Select(x => SearchItemVm.Create(x, x.UnitType, propNames))
                .ToList();

            return SearchVm.Create(result, total);
        }

        public async Task<List<UnitLookupVm>> Search(string code, int limit = 5)
        {
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.StatId != null
                    && unit.StatId.StartsWith(code, StringComparison.OrdinalIgnoreCase)
                    && unit.ParrentId == null
                    && !unit.IsDeleted;
            var units = _readCtx.StatUnits.Where(filter).Select(UnitMapping);
            var eg = _readCtx.EnterpriseGroups.Where(filter).Select(UnitMapping);
            var list = await units.Concat(eg).Take(limit).ToListAsync();
            return ToUnitLookupVm(list).ToList();
        }
    }
}
