using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.StatUnits.Search;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Класс сервис поиска
    /// </summary>
    public class SearchService
    {
        private readonly UserService _userService;
        private readonly NSCRegDbContext _dbContext;
        private readonly ElasticService _elasticService;

        public SearchService(NSCRegDbContext dbContext)
        {
            _userService = new UserService(dbContext);
            _dbContext = dbContext;
            _elasticService = new ElasticService(dbContext);
        }

        /// <summary>
        /// Метод поиска стат. единицы
        /// </summary>
        /// <param name="filter">Запрос</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="isDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public async Task<SearchVm> Search(SearchQueryM filter, string userId, bool isDeleted = false)
        {
            bool isAdmin = await _userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator);

            long totalCount;
            List<ElasticStatUnit> units;
            if (filter.IsEmpty())
            {
                var baseQuery = _dbContext.StatUnitSearchView
                    .Where(s => s.IsDeleted == isDeleted);

                if (!isAdmin)
                {
                    var regionIds = await _dbContext.UserRegions.Where(au => au.UserId == userId).Select(ur => ur.RegionId).ToListAsync();
                    baseQuery = baseQuery.Where(s => s.RegionId.HasValue && regionIds.Contains(s.RegionId.Value));
                }

                totalCount = baseQuery.Count();
                units = (await baseQuery.Skip((filter.Page - 1) * filter.PageSize).Take(filter.PageSize).ToListAsync())
                    .Select(Mapper.Map<StatUnitSearchView, ElasticStatUnit>).ToList();
            }
            else
            {
                var searchResponse = await _elasticService.Search(filter, userId, isDeleted, isAdmin);
                totalCount = searchResponse.TotalCount;
                units = searchResponse.Result.ToList();
            }

            var finalIds = units.Where(x => x.UnitType != StatUnitTypes.EnterpriseGroup)
                .Select(x => x.RegId).ToList();
            var finalRegionIds = units.Select(x => x.RegionId).ToList();

            var unitsToPersonNames = await GetUnitsToPersonNamesByUnitIds(finalIds);

            var unitsToMainActivities = await GetUnitsToPrimaryActivities(finalIds);

            var regions = await GetRegionsFullPaths(finalRegionIds);

            var permissions = await _userService.GetDataAccessAttributes(userId, null);
            var result = units
                .Select(x => new SearchViewAdapterModel(x, unitsToPersonNames[x.RegId],
                    unitsToMainActivities[x.RegId],
                    regions.GetValueOrDefault(x.RegionId)))
                .Select(x => SearchItemVm.Create(x, x.UnitType, permissions.GetReadablePropNames()));

            return SearchVm.Create(result, totalCount);
        }

        private async Task<IDictionary<int?, RegionLookupVm>> GetRegionsFullPaths(ICollection<int?> finalRegionIds)
        {
            var regionIds = finalRegionIds.Where(x => x.HasValue).Select(x => x.Value).ToList();
            var regionPaths = await _dbContext.Regions.Where(x => regionIds.Contains(x.Id))
                .Select(x => new {x.Id, x.FullPath, x.FullPathLanguage1, x.FullPathLanguage2}).ToListAsync();
            return regionPaths
                .ToDictionary(x => (int?) x.Id, x => new RegionLookupVm
                {
                    FullPath = x.FullPath,
                    FullPathLanguage1 = x.FullPathLanguage1,
                    FullPathLanguage2 = x.FullPathLanguage2
                });
        }

        private async Task<ILookup<int, CodeLookupVm>> GetUnitsToPrimaryActivities(ICollection<int> regIds)
        {
            var unitsActivities = await _dbContext.ActivityStatisticalUnits
                .Where(x => regIds.Contains(x.UnitId) && x.Activity.ActivityType == ActivityTypes.Primary)
                .Select(x => new {x.UnitId, x.Activity.ActivityCategory.Code, x.Activity.ActivityCategory.Name, x.Activity.ActivityCategory.NameLanguage1, x.Activity.ActivityCategory.NameLanguage2 })
                .ToListAsync();
            return unitsActivities
                .ToLookup(x => x.UnitId, x => new CodeLookupVm()
                {
                    Code = x.Code,
                    Name = $"{x.Code} {x.Name}",
                    NameLanguage1 = $"{x.Code} {x.NameLanguage1}",
                    NameLanguage2 = $"{x.Code} {x.NameLanguage2}"
                });
        }

        private async Task<ILookup<int, string>> GetUnitsToPersonNamesByUnitIds(ICollection<int> regIds)
        {
            var personNames = await _dbContext.PersonStatisticalUnits
                .Where(x => regIds.Contains(x.UnitId))
                .Select(x => new {x.UnitId, Name = x.Person.GivenName ?? x.EnterpriseGroup.Name ?? x.StatUnit.Name })
                .ToListAsync();
            return personNames.ToLookup(x => x.UnitId, x => x.Name);
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
        public async Task<List<UnitLookupVm>> SearchByWildcard(string wildcard, int limit = 5)
        {
            var loweredwc = wildcard.ToLower();
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit => !unit.IsDeleted &&
                    (unit.Name != null && unit.Name.ToLower().Contains(loweredwc) || unit.StatId.StartsWith(loweredwc));
            var units = _dbContext.StatisticalUnits.Where(filter).GroupBy(s => s.StatId).Select(g => g.First())
                .Select(Common.UnitMapping);
            var eg = _dbContext.EnterpriseGroups.Where(filter).GroupBy(s => s.StatId).Select(g => g.First())
                .Select(Common.UnitMapping);
            var list = await units.Concat(eg).OrderBy(o => o.Item1.Code).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }

        /// <summary>
        /// Validates provided statId uniqueness
        /// </summary>
        /// <param name="unitType"></param>
        /// <param name="statId"></param>
        /// <param name="unitId"></param>
        /// <returns></returns>
        public async Task<bool> ValidateStatIdUniquenessAsync(int? unitId, StatUnitTypes unitType, string statId)
        {
            if (unitType == StatUnitTypes.EnterpriseGroup)
            {
                return !await _dbContext.EnterpriseGroups
                    .AnyAsync(x => x.StatId == statId && x.RegId != unitId);
            }
            return !await _dbContext.StatisticalUnits
                .AnyAsync(x => x.StatId == statId && x.RegId != unitId && x.UnitType == unitType);
        }
    }
}
