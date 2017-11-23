using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Dynamic.Core;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Business.PredicateBuilders;
using nscreg.Data.Constants;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Класс сервис поиска
    /// </summary>
    public class SearchService
    {
        private readonly UserService _userService;
        private readonly NSCRegDbContext _dbContext;


        public SearchService(NSCRegDbContext dbContext)
        {
            _userService = new UserService(dbContext);
            _dbContext = dbContext;
        }

        /// <summary>
        /// Метод поиска стат. единицы
        /// </summary>
        /// <param name="query">Запрос</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="deletedOnly">Флаг удалённости</param>
        /// <returns></returns>
        public async Task<SearchVm> Search(SearchQueryM query, string userId, bool deletedOnly = false)
        {
            
            var permissions = await _userService.GetDataAccessAttributes(userId, null);
            var suPredicateBuilder = new SearchPredicateBuilder<StatisticalUnit>();
            var statUnitPredicate = suPredicateBuilder.GetPredicate(query.TurnoverFrom, query.TurnoverTo,
                query.EmployeesNumberFrom, query.EmployeesNumberTo, query.Comparison);

            var filtered = _dbContext.StatUnitSearchView
                .Where(x => x.ParentId == null && x.IsDeleted == deletedOnly)
                .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason));

            filtered = (IQueryable<StatUnitSearchView>) (statUnitPredicate == null ? filtered : filtered.Where(statUnitPredicate));

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                var wildcard = query.Wildcard.ToLower();

                filtered = filtered.Where(x =>
                    x.Name.ToLower().Contains(wildcard)
                    || x.StatId.ToLower().Contains(wildcard)
                    || x.TaxRegId.ToLower().Contains(wildcard)
                    || x.ExternalId.ToLower().Contains(wildcard)
                    || x.AddressPart1.ToLower().Contains(wildcard)
                    || x.AddressPart2.ToLower().Contains(wildcard)
                    || x.AddressPart3.ToLower().Contains(wildcard));
            }

            if (query.Type.HasValue)
                filtered = filtered.Where(x => x.UnitType == query.Type);

            if (query.SectorCodeId.HasValue)
                filtered = filtered.Where(x => x.SectorCodeId == query.SectorCodeId);

            if (query.LegalFormId.HasValue)
                filtered = filtered.Where(x => x.LegalFormId == query.LegalFormId);

            if (query.RegMainActivityId.HasValue)
            {
                var activitiesId = await _dbContext.Activities.Where(x => x.ActivityCategoryId == query.RegMainActivityId).Select(x => x.Id)
                    .ToListAsync();
                var statUnitsIds = await _dbContext.ActivityStatisticalUnits.Where(x => activitiesId.Contains(x.ActivityId))
                    .Select(x => x.UnitId).ToListAsync();
                filtered = filtered.Where(x => statUnitsIds.Contains(x.RegId));
            }

            if (query.LastChangeFrom.HasValue)
                filtered = filtered.Where(x => x.StartPeriod >= query.LastChangeFrom);

            if (query.LastChangeTo.HasValue)
                filtered = filtered.Where(x => x.StartPeriod.Date <= query.LastChangeTo);

            if (!string.IsNullOrEmpty(query.DataSource))
                filtered = filtered.Where(x => x.DataSource != null && x.DataSource.ToLower().Contains(query.DataSource.ToLower()));

            if (query.RegionId.HasValue)
            {
                var regionId = _dbContext.Regions.FirstOrDefault(x => x.Id == query.RegionId).Id;
                filtered = filtered.Where(x => x.RegionId == regionId);
            }

            int total = 0;

            if (!await _userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator))
            {
               var ids = 
                    from asu in _dbContext.ActivityStatisticalUnits 
                    join act in _dbContext.Activities on asu.ActivityId equals act.Id
                    join au in _dbContext.ActivityCategoryUsers on act.ActivityCategoryId equals au.ActivityCategoryId
                    where au.UserId == userId
                    select asu.UnitId;

                var regionIds = from ur in _dbContext.UserRegions
                    where ur.UserId == userId
                    select ur.RegionId;

                var filteredViewItemsForCount =
                    filtered.Where(v => ids.Contains(v.RegId) && regionIds.Contains(v.RegionId.Value));
                var filteredEntGroupsForCount = filtered.Where(v => v.UnitType == StatUnitTypes.EnterpriseGroup);



                filtered = filtered.Where(v =>
                    v.UnitType == StatUnitTypes.EnterpriseGroup ||
                    ids.Contains(v.RegId) && regionIds.Contains(v.RegionId.Value));
                var totalNonEnterpriseGroups = filteredViewItemsForCount.Count();
                var totalEnterpriseGroups = filteredEntGroupsForCount.Count();
                total = totalNonEnterpriseGroups + totalEnterpriseGroups;
            }
            else
            {
                total = filtered.Count();
            }
           
           
            
            
            var take = query.PageSize;
            var skip = query.PageSize * (query.Page - 1);

            var result = filtered
                .OrderBy(query.SortBy, query.SortRule)
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(query.PageSize)
                .Select(x => SearchItemVm.Create(x, x.UnitType, permissions.GetReadablePropNames()))
                .ToList();
            return SearchVm.Create(result, total);
        }

        /// <summary>
        /// Метод поиска стат. единицы по коду
        /// </summary>
        /// <param name="code">Код</param>
        /// <param name="limit">Ограничение отображаемости</param>
        /// <returns></returns>
        public async Task<List<UnitLookupVm>> Search(string code, int limit = 5)
        {
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.StatId != null
                    && unit.StatId.StartsWith(code, StringComparison.OrdinalIgnoreCase)
                    && unit.ParentId == null
                    && !unit.IsDeleted;
            var units = _dbContext.StatisticalUnits.Where(filter).Select(Common.UnitMapping);
            var eg = _dbContext.EnterpriseGroups.Where(filter).Select(Common.UnitMapping);
            var list = await units.Concat(eg).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }

        /// <summary>
        /// Метод поиска стат. единицы по имени
        /// </summary>
        /// <param name="wildcard">Шаблон поиска</param>
        /// <param name="limit">Ограничение отображаемости</param>
        /// <returns></returns>
        public async Task<List<UnitLookupVm>> SearchByName(string wildcard, int limit = 5)
        {
            var loweredwc = wildcard.ToLower();
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.Name != null
                    && unit.Name.ToLower().Contains(loweredwc)
                    && !unit.IsDeleted;
            var units = _dbContext.StatisticalUnits.Where(filter).GroupBy(s => s.StatId).Select(g => g.First()).Select(Common.UnitMapping);
            var eg = _dbContext.EnterpriseGroups.Where(filter).GroupBy(s=> s.StatId).Select(g => g.First()).Select(Common.UnitMapping);
            var list = await units.Concat(eg).OrderBy(o => o.Item1.Name).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }
       
    }
}
