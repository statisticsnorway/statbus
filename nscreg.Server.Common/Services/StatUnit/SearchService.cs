using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class SearchService
    {
        private readonly ReadContext _readCtx;
        private readonly UserService _userService;
        private readonly Common _commonSvc;


        public SearchService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
            _userService = new UserService(dbContext);
            _commonSvc = new Common(dbContext);

        }

        public async Task<SearchVm> Search(SearchQueryM query, string userId, bool deletedOnly = false)
        {
            var propNames = await _userService.GetDataAccessAttributes(userId, null);

            var list = new List<IStatisticalUnit>();

            list.AddRange(await SearchUnitFilterApply(
                    query,
                    deletedOnly,
                    _commonSvc.GetUnitsList<LocalUnit>(deletedOnly)
                        .Include(x => x.Address)
                        .Include(x => x.LegalUnit)
                        .ThenInclude(x => x.EnterpriseUnit)
                        .ThenInclude(x => x.EnterpriseGroup)
                        .Include(x => x.LegalUnit)
                        .ThenInclude(x => x.EnterpriseGroup)
                        .Include(x => x.EnterpriseUnit)
                        .ThenInclude(x => x.EnterpriseGroup))
                .ToListAsync());

            list.AddRange(await SearchUnitFilterApply(
                    query,
                    deletedOnly,
                    _commonSvc.GetUnitsList<LegalUnit>(deletedOnly)
                        .Include(x => x.Address)
                        .Include(x => x.EnterpriseGroup)
                        .Include(x => x.EnterpriseUnit)
                        .ThenInclude(x => x.EnterpriseGroup))
                .ToListAsync());

            list.AddRange(
                await SearchUnitFilterApply(query, deletedOnly,
                    _commonSvc.GetUnitsList<EnterpriseUnit>(deletedOnly)
                        .Include(x => x.EnterpriseGroup)
                        .Include(x => x.Address))
                    .ToListAsync());

            list.AddRange(
                await SearchUnitFilterApply(query, deletedOnly, 
                    _commonSvc.GetUnitsList<EnterpriseGroup>(deletedOnly)
                        .Include(x => x.Address))
                    .ToListAsync());

            
            var total = list.Count();
            var take = query.PageSize;
            var skip = query.PageSize * (query.Page - 1);

            

            var result = list
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(query.PageSize)
                .Select(x => SearchItemVm.Create(x, x.UnitType, propNames))
                .ToList();

            return SearchVm.Create(result, total);
        }

        private static IQueryable<T> SearchUnitFilterApply<T>(SearchQueryM query, bool deletedOnly, IQueryable<T> filtered)
            where T : IStatisticalUnit
        {
            filtered = filtered.Where(x => (x.ParrentId == null && x.IsDeleted == deletedOnly) && 
                                           (query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason)));

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                Predicate<string> checkWildcard =
                    superStr => !string.IsNullOrEmpty(superStr) && superStr.ToLower().Contains(query.Wildcard.ToLower());
                filtered = filtered.Where(x =>
                    x.Name.ToLower().Contains(query.Wildcard.ToLower())
                    || checkWildcard(x.StatId)
                    || checkWildcard(x.TaxRegId)
                    || checkWildcard(x.ExternalId)
                    || x.Address != null
                    && (checkWildcard(x.Address.AddressPart1)
                        || checkWildcard(x.Address.AddressPart2)
                        || checkWildcard(x.Address.AddressPart3)));
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

            if (query.SectorCodeId.HasValue)
                filtered = filtered.Where(x => x.InstSectorCodeId == query.SectorCodeId);

            if (query.LegalFormId.HasValue)
                filtered = filtered.Where(x => x.LegalFormId == query.LegalFormId);

            if (query.RegMainActivityId.HasValue)
                filtered = filtered.Where(x => x.RegMainActivityId == query.RegMainActivityId);

            if (query.LastChangeFrom.HasValue)
                filtered = filtered.Where(x => x.StartPeriod >= query.LastChangeFrom);

            if (query.LastChangeTo.HasValue)
                filtered = filtered.Where(x => x.StartPeriod <= query.LastChangeTo);

            if (!string.IsNullOrEmpty(query.DataSource))
                filtered = filtered.Where(x => x.DataSource != null && x.DataSource.ToLower().Contains(query.DataSource.ToLower()));

            if (!string.IsNullOrEmpty(query.RegionCode))
                filtered = filtered.Where(x => x.Address.Region.Code == query.RegionCode);

            return filtered;
        }

        public async Task<List<UnitLookupVm>> Search(string code, int limit = 5)
        {
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.StatId != null
                    && unit.StatId.StartsWith(code, StringComparison.OrdinalIgnoreCase)
                    && unit.ParrentId == null
                    && !unit.IsDeleted;
            var units = _readCtx.StatUnits.Where(filter).Select(Common.UnitMapping);
            var eg = _readCtx.EnterpriseGroups.Where(filter).Select(Common.UnitMapping);
            var list = await units.Concat(eg).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }

        public async Task<List<UnitLookupVm>> SearchByName(string wildcard, int limit = 5)
        {
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.Name != null
                    && unit.Name.StartsWith(wildcard, StringComparison.OrdinalIgnoreCase)
                    && !unit.IsDeleted;
            var units = _readCtx.StatUnits.Where(filter).Select(Common.UnitMapping);
            var eg = _readCtx.EnterpriseGroups.Where(filter).Select(Common.UnitMapping);
            var list = await units.Concat(eg).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }
    }
}
