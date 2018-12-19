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
using nscreg.Utilities.Enums.Predicate;
using nscreg.Utilities.Extensions;
using Nest;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Класс сервис поиска
    /// </summary>
    public class SearchService
    {
        private readonly UserService _userService;
        private readonly NSCRegDbContext _dbContext;
        private readonly ElasticClient _elasticClient;
        private readonly string _indexName = nameof(StatUnitSearchView).ToLower();

        public SearchService(NSCRegDbContext dbContext)
        {
            _userService = new UserService(dbContext);
            _dbContext = dbContext;

            var settings = new ConnectionSettings(new Uri("http://localhost:9200")).DefaultIndex(_indexName).DisableDirectStreaming();
            _elasticClient = new ElasticClient(settings);
        }

        public async Task<int> SynchronizeElasticWithDatabase()
        {
            var baseQuery = _dbContext.StatUnitSearchView.Where(s => !s.ParentId.HasValue);
            int dbCount = baseQuery.Count();
            var elasticsCount = await _elasticClient.CountAsync<ElasticStatUnit>();
            if (dbCount == elasticsCount.Count)
                return dbCount;

            var deleteResponse = await _elasticClient.DeleteIndexAsync(_indexName);

            var activitiStaticalUnits = _dbContext.ActivityStatisticalUnits
                .Select(a => new {a.UnitId, a.Activity.ActivityCategoryId})
                .ToLookup(a => a.UnitId, a => a.ActivityCategoryId);

            const int batchSize = 50000;

            var query = baseQuery.AsNoTracking().AsEnumerable();
            int currentButchSize = 0;

            var descriptor = new BulkDescriptor();
            foreach (var item in query)
            {
                var elasticItem = Mapper.Map<StatUnitSearchView, ElasticStatUnit>(item);
                elasticItem.ActivityCategoryIds = elasticItem.UnitType == StatUnitTypes.EnterpriseGroup
                    ? new List<int>()
                    : activitiStaticalUnits[elasticItem.RegId].ToList();
                descriptor.Index<ElasticStatUnit>(op => op.Document(elasticItem));
                ++currentButchSize;
                if (currentButchSize < batchSize)
                    continue;

                var bulkResponse = await _elasticClient.BulkAsync(descriptor);
                descriptor = new BulkDescriptor();
                currentButchSize = 0;
            }

            if(currentButchSize > 0)
                await _elasticClient.BulkAsync(descriptor);

            return dbCount;
        }

        /// <summary>
        /// Метод поиска стат. единицы
        /// </summary>
        /// <param name="filter">Запрос</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="deletedOnly">Флаг удалённости</param>
        /// <returns></returns>
        public async Task<SearchVm> Search(SearchQueryM filter, string userId, bool deletedOnly = false)
        {
            await SynchronizeElasticWithDatabase();

            var mustQueries = new List<Func<QueryContainerDescriptor<ElasticStatUnit>, QueryContainer>>();

            if (!await _userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator))
            {
                var regionIds = await _dbContext.UserRegions.Where(au => au.UserId == userId).Select(ur => ur.RegionId).ToListAsync();

                var activityIds = await _dbContext.ActivityCategoryUsers.Where(au => au.UserId == userId).Select(au => au.ActivityCategoryId).ToListAsync();

                mustQueries.Add(m => m.Terms(t => t.Field(f => f.RegionId).Terms(regionIds)));

                mustQueries.Add(m => m
                    .Bool(b => b
                        .Should(s => s.Term(t => t.Field(f => f.UnitType).Value(StatUnitTypes.EnterpriseGroup)))
                        .Should(s => s.Terms(t => t.Field(f => f.ActivityCategoryIds).Terms(activityIds)))
                    )
                );
            }

            var separators = new[] {' ', '\t', '\r', '\n', '.'};

            if (!string.IsNullOrWhiteSpace(filter.Name))
            {
                var nameFilterParts = filter.Name.ToLower().Split(separators, StringSplitOptions.RemoveEmptyEntries);
                foreach (var nameFilter in nameFilterParts)
                    mustQueries.Add(m => m.Prefix(p => p.Field(f => f.Name).Value(nameFilter)));
            }

            if (!string.IsNullOrWhiteSpace(filter.StatId))
                mustQueries.Add(m => m.Prefix(p => p.Field(f => f.StatId).Value(filter.StatId.ToLower())));

            if (!string.IsNullOrWhiteSpace(filter.ExternalId))
                mustQueries.Add(m => m.Prefix(p => p.Field(f => f.ExternalId).Value(filter.ExternalId.ToLower())));

            if(!string.IsNullOrWhiteSpace(filter.TaxRegId))
                mustQueries.Add(m => m.Prefix(p => p.Field(f => f.TaxRegId).Value(filter.TaxRegId.ToLower())));

            if (!string.IsNullOrWhiteSpace(filter.Address))
            {
                string[] addressFilters = filter.Address.ToLower().Split(separators, StringSplitOptions.RemoveEmptyEntries);
                foreach (var addressFilter in addressFilters)
                {
                    mustQueries.Add(m => m
                        .Bool(b => b
                            .Should(s => s.Prefix(t => t.Field(f => f.AddressPart1).Value(addressFilter)))
                            .Should(s => s.Prefix(t => t.Field(f => f.AddressPart2).Value(addressFilter)))
                            .Should(s => s.Prefix(t => t.Field(f => f.AddressPart3).Value(addressFilter)))
                        )
                    );
                }
            }

            var turnoverQueries = new List<Func<QueryContainerDescriptor<ElasticStatUnit>, QueryContainer>>();
            if (filter.TurnoverFrom.HasValue)
                turnoverQueries.Add(m => m.Range(p => p.Field(f => f.Turnover).GreaterThanOrEquals((double)filter.TurnoverFrom.Value)));
            if (filter.TurnoverTo.HasValue)
                turnoverQueries.Add(m => m.Range(p => p.Field(f => f.Turnover).LessThanOrEquals((double)filter.TurnoverTo.Value)));

            var employeeQueries = new List<Func<QueryContainerDescriptor<ElasticStatUnit>, QueryContainer>>();
            if (filter.EmployeesNumberFrom.HasValue)
                employeeQueries.Add(m => m.Range(p => p.Field(f => f.Employees).GreaterThanOrEquals((double)filter.EmployeesNumberFrom.Value)));
            if (filter.EmployeesNumberTo.HasValue)
                employeeQueries.Add(m => m.Range(p => p.Field(f => f.Employees).LessThanOrEquals((double)filter.EmployeesNumberTo.Value)));
            if (filter.Comparison == ComparisonEnum.And || turnoverQueries.Count == 0 || employeeQueries.Count == 0)
            {
                mustQueries.AddRange(turnoverQueries);
                mustQueries.AddRange(employeeQueries);
            }
            else
                mustQueries.Add(m => m.Bool(b => b.Should(s => s.Bool(b1 => b1.Must(turnoverQueries)), s => s.Bool(b2 => b2.Must(employeeQueries)))));

            if (filter.LastChangeFrom.HasValue)
                mustQueries.Add(m => m.DateRange(p => p.Field(f => f.StartPeriod).GreaterThanOrEquals(filter.LastChangeFrom.Value)));

            if (filter.LastChangeTo.HasValue)
                mustQueries.Add(m => m.DateRange(p => p.Field(f => f.StartPeriod).LessThanOrEquals(filter.LastChangeTo.Value)));

            if(filter.DataSourceClassificationId.HasValue)
                mustQueries.Add(m => m.Term(p => p.Field(f => f.DataSourceClassificationId).Value(filter.DataSourceClassificationId.Value)));

            if(!filter.IncludeLiquidated)
                mustQueries.Add(m => m.Term(p => p.Field(f => f.IsLiquidated).Value(false)));

            if(filter.RegMainActivityId.HasValue)
                mustQueries.Add(m => m.Terms(p => p.Field(f => f.ActivityCategoryIds).Terms(new []{ filter.RegMainActivityId.Value })));

            if(filter.SectorCodeId.HasValue)
                mustQueries.Add(m => m.Term(p => p.Field(f => f.SectorCodeId).Value(filter.SectorCodeId.Value)));

            if (filter.LegalFormId.HasValue)
                mustQueries.Add(m => m.Term(p => p.Field(f => f.LegalFormId).Value(filter.LegalFormId.Value)));

            var searchResponse = await _elasticClient.SearchAsync<ElasticStatUnit>(s =>
                s.From(filter.PageSize * filter.Page - filter.PageSize).Take(filter.PageSize).Query(q => q.Bool(b => b.Must(mustQueries)))
            );

            var units = searchResponse.Documents.ToList();

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

            return SearchVm.Create(result, searchResponse.Total);

//            var permissions = await _userService.GetDataAccessAttributes(userId, null);
//            var suPredicateBuilder = new SearchPredicateBuilder<StatUnitSearchView>();
//            var statUnitPredicate = suPredicateBuilder.GetPredicate(
//                query.TurnoverFrom,
//                query.TurnoverTo,
//                query.EmployeesNumberFrom,
//                query.EmployeesNumberTo,
//                query.Comparison);
//
//            var filtered = _dbContext.StatUnitSearchView
//                .Where(x => x.ParentId == null
//                            && x.IsDeleted == deletedOnly
//                            && (query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason)));
//
//            filtered = statUnitPredicate == null
//                ? filtered
//                : filtered.Where(statUnitPredicate);
//
//
//            filtered = GetWildcardFilter(query, filtered);
//
//            if (query.RegMainActivityId.HasValue) // TODO: write as plain LINQ?
//            {
//                var activitiesId = await _dbContext.Activities
//                    .Where(x => x.ActivityCategoryId == query.RegMainActivityId)
//                    .Select(x => x.Id)
//                    .ToListAsync();
//                var statUnitsIds = await _dbContext.ActivityStatisticalUnits
//                    .Where(x => activitiesId.Contains(x.ActivityId))
//                    .Select(x => x.UnitId)
//                    .ToListAsync();
//                filtered = filtered.Where(x => statUnitsIds.Contains(x.RegId));
//            }
//
//            if (query.RegionId.HasValue) // TODO: write as plain LINQ?
//            {
//                var regionId = (await _dbContext.Regions.FirstOrDefaultAsync(x => x.Id == query.RegionId)).Id;
//                filtered = filtered.Where(x => x.RegionId == regionId);
//            }
//
//            int total;
//
//            if (await _userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator))
//            {
//                total = await filtered.CountAsync();
//            }
//            else
//            {
//                var ids =
//                    from asu in _dbContext.ActivityStatisticalUnits
//                    join act in _dbContext.Activities on asu.ActivityId equals act.Id
//                    join au in _dbContext.ActivityCategoryUsers on act.ActivityCategoryId equals au.ActivityCategoryId
//                    where au.UserId == userId
//                    select asu.UnitId;
//
//                var regionIds = from ur in _dbContext.UserRegions
//                    where ur.UserId == userId
//                    select ur.RegionId;
//
//                var filteredViewItemsForCount =
//                    filtered.Where(v => ids.Contains(v.RegId) && regionIds.Contains(v.RegionId.Value));
//                var filteredEntGroupsForCount = filtered.Where(v => v.UnitType == StatUnitTypes.EnterpriseGroup);
//
//                filtered = filtered.Where(v =>
//                    v.UnitType == StatUnitTypes.EnterpriseGroup ||
//                    ids.Contains(v.RegId) && regionIds.Contains(v.RegionId.Value));
//                var totalNonEnterpriseGroups = await filteredViewItemsForCount.CountAsync();
//                var totalEnterpriseGroups = await filteredEntGroupsForCount.CountAsync();
//                total = totalNonEnterpriseGroups + totalEnterpriseGroups;
//            }
//
//            var units = await filtered.OrderBy(query.SortBy, query.SortRule)
//                    .Skip(Pagination.CalculateSkip(query.PageSize, query.Page, total))
//                    .Take(query.PageSize)
//                    .ToListAsync();
//
//            var finalIds = units.Where(x => x.UnitType != StatUnitTypes.EnterpriseGroup)
//                .Select(x => x.RegId).ToList();
//            var finalRegionIds = units.Select(x => x.RegionId).ToList();
//
//            var unitsToPersonNames = await GetUnitsToPersonNamesByUnitIds(finalIds);
//
//            var unitsToMainActivities = await GetUnitsToPrimaryActivities(finalIds);
//
//            var regions = await GetRegionsFullPaths(finalRegionIds);
//
//            var result = units
//                .Select(x => new SearchViewAdapterModel(x, unitsToPersonNames[x.RegId],
//                    unitsToMainActivities[x.RegId],
//                    regions.GetValueOrDefault(x.RegionId)))
//                .Select(x => SearchItemVm.Create(x, x.UnitType, permissions.GetReadablePropNames()));
//
//            return SearchVm.Create(result, total);
        }

        private static IQueryable<StatUnitSearchView> GetWildcardFilter(SearchQueryM query,
            IQueryable<StatUnitSearchView> filtered)
        {
            var lowerName = query.Name?.ToLower();
            var statId = query.StatId;
            var taxRegId = query.TaxRegId;
            var extId = query.ExternalId;
            var lowerAddress = query.Address?.ToLower();
            return filtered.Where(x => (string.IsNullOrEmpty(query.Name) || x.Name.ToLower().Contains(lowerName))
                                       && (string.IsNullOrEmpty(query.StatId) ||
                                           x.StatId == statId)
                                       && (string.IsNullOrEmpty(query.TaxRegId) ||
                                           x.TaxRegId==taxRegId)
                                       && (string.IsNullOrEmpty(query.ExternalId) ||
                                           x.ExternalId == extId)
                                       && (string.IsNullOrEmpty(query.Address)
                                           || x.AddressPart1.ToLower().Contains(lowerAddress)
                                           || x.AddressPart2.ToLower().Contains(lowerAddress)
                                           || x.AddressPart3.ToLower().Contains(lowerAddress))
                                       && (query.DataSourceClassificationId == null ||
                                           x.DataSourceClassificationId == query.DataSourceClassificationId)
                                       && (query.LegalFormId == null || x.LegalFormId == query.LegalFormId)
                                       && (query.SectorCodeId == null || x.SectorCodeId == query.SectorCodeId)
                                       && (query.Type == null || x.UnitType == query.Type)
                                       && (query.LastChangeFrom == null || x.StartPeriod >= query.LastChangeFrom)
                                       && (query.LastChangeTo == null || x.StartPeriod.Date <= query.LastChangeTo));
        }

        private async Task<IDictionary<int?, RegionLookupVm>> GetRegionsFullPaths(ICollection<int?> finalRegionIds)
        {
            var regionIds = finalRegionIds.Where(x => x.HasValue).Select(x => x.Value).ToList();
            var regionPaths = await _dbContext.Regions.Where(x => regionIds.Contains(x.Id))
                .Select(x => new {x.Id, x.FullPath, x.FullPathLanguage1, x.FullPathLanguage2}).ToListAsync();
            return regionPaths
                .ToDictionary(x => (int?) x.Id, x => new RegionLookupVm()
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
                .Where(x => regIds.Contains(x.UnitId) && x.PersonType == PersonTypes.ContactPerson)
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
        public async Task<List<UnitLookupVm>> SearchByWildcard(string wildcard, int limit = 5)
        {
            var loweredwc = wildcard.ToLower();
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit => !unit.IsDeleted && unit.ParentId == null &&
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
                    .AnyAsync(x => x.StatId == statId && x.ParentId == null && x.RegId != unitId);
            }
            return !await _dbContext.StatisticalUnits
                .AnyAsync(x => x.StatId == statId && x.ParentId == null && x.RegId != unitId && x.UnitType == unitType);
        }
    }
}
