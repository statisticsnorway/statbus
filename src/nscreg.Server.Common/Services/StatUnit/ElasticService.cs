using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Server.Common.Models;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Enums.Predicate;
using Nest;

namespace nscreg.Server.Common.Services.StatUnit
{
    internal class ElasticService
    {
        private readonly UserService _userService;
        private readonly NSCRegDbContext _dbContext;
        private readonly ElasticClient _elasticClient;
        private readonly string _indexName = nameof(StatUnitSearchView).ToLower();

        public ElasticService(NSCRegDbContext dbContext, UserService userService)
        {
            _dbContext = dbContext;
            _userService = userService;

            var settings = new ConnectionSettings(new Uri("http://localhost:9200")).DefaultIndex(_indexName).DisableDirectStreaming();
            _elasticClient = new ElasticClient(settings);
        }

        public async Task<int> SynchronizeElasticToDatabase()
        {
            var baseQuery = _dbContext.StatUnitSearchView.Where(s => !s.ParentId.HasValue);
            int dbCount = baseQuery.Count();
            var elasticsCount = await _elasticClient.CountAsync<ElasticStatUnit>();
            if (dbCount == elasticsCount.Count)
                return dbCount;

            var deleteResponse = await _elasticClient.DeleteIndexAsync(_indexName);
            if (!deleteResponse.IsValid)
                throw new Exception(deleteResponse.DebugInformation);

            var activityCategoryStaticalUnits = _dbContext.ActivityStatisticalUnits
                .Select(a => new { a.UnitId, a.Activity.ActivityCategoryId })
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
                    : activityCategoryStaticalUnits[elasticItem.RegId].ToList();
                descriptor.Index<ElasticStatUnit>(op => op.Document(elasticItem));
                ++currentButchSize;
                if (currentButchSize < batchSize)
                    continue;

                var bulkResponse = await _elasticClient.BulkAsync(descriptor);
                if (!bulkResponse.IsValid)
                    throw new Exception(bulkResponse.DebugInformation);

                descriptor = new BulkDescriptor();
                currentButchSize = 0;
            }

            if (currentButchSize > 0)
                await _elasticClient.BulkAsync(descriptor);

            return dbCount;
        }

        public async Task SynchronizeDocumentToDatabase(int itemId, StatUnitTypes unitType)
        {
            StatUnitSearchView item = _dbContext.StatUnitSearchView.FirstOrDefault(i => i.RegId == itemId && i.UnitType == unitType);
            var elasticItem = Mapper.Map<StatUnitSearchView, ElasticStatUnit>(item);

            elasticItem.ActivityCategoryIds = elasticItem.UnitType == StatUnitTypes.EnterpriseGroup
                ? new List<int>()
                : await _dbContext.ActivityStatisticalUnits
                    .Where(a => a.UnitId == item.RegId)
                    .Select(a => a.Activity.ActivityCategoryId)
                    .ToListAsync();

            var updateResult = await _elasticClient.UpdateAsync<ElasticStatUnit, ElasticStatUnit>(elasticItem.Id, u => u.Doc(elasticItem));
            if (!updateResult.IsValid)
                throw new Exception(updateResult.DebugInformation);
        }

        public async Task<SearchVm<ElasticStatUnit>> Search(SearchQueryM filter, string userId)
        {
            var mustQueries = new List<Func<QueryContainerDescriptor<ElasticStatUnit>, QueryContainer>>();

            bool isAdmin = await _userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator);

            if (!isAdmin)
            {
                var regionIdsQuery = _dbContext.UserRegions.Where(au => au.UserId == userId);

                if (filter.RegionId.HasValue)
                    regionIdsQuery = regionIdsQuery.Where(au => au.RegionId == filter.RegionId.Value);

                var regionIds = await regionIdsQuery.Select(ur => ur.RegionId).ToListAsync();

                var activityIds = await _dbContext.ActivityCategoryUsers.Where(au => au.UserId == userId).Select(au => au.ActivityCategoryId).ToListAsync();

                mustQueries.Add(m => m.Terms(t => t.Field(f => f.RegionId).Terms(regionIds)));

                mustQueries.Add(m => m
                    .Bool(b => b
                        .Should(s => s.Term(t => t.Field(f => f.UnitType).Value(StatUnitTypes.EnterpriseGroup)))
                        .Should(s => s.Terms(t => t.Field(f => f.ActivityCategoryIds).Terms(activityIds)))
                    )
                );
            }

            var separators = new[] { ' ', '\t', '\r', '\n', '.' };

            if (!string.IsNullOrWhiteSpace(filter.Name))
            {
                var nameFilterParts = filter.Name.ToLower().Split(separators, StringSplitOptions.RemoveEmptyEntries);
                foreach (var nameFilter in nameFilterParts)
                    mustQueries.Add(m => m.Prefix(p => p.Field(f => f.Name).Value(nameFilter)));
            }

            if (filter.Type.HasValue)
                mustQueries.Add(m => m.Term(p => p.Field(f => f.UnitType).Value(filter.Type.Value)));

            if (!string.IsNullOrWhiteSpace(filter.StatId))
                mustQueries.Add(m => m.Prefix(p => p.Field(f => f.StatId).Value(filter.StatId.ToLower())));

            if (!string.IsNullOrWhiteSpace(filter.ExternalId))
                mustQueries.Add(m => m.Prefix(p => p.Field(f => f.ExternalId).Value(filter.ExternalId.ToLower())));

            if (!string.IsNullOrWhiteSpace(filter.TaxRegId))
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
            {
                double turnoverFrom = (double)filter.TurnoverFrom.Value;
                turnoverQueries.Add(m => m.Range(p => p.Field(f => f.Turnover).GreaterThanOrEquals(turnoverFrom)));
            }
            if (filter.TurnoverTo.HasValue)
            {
                double turnoverTo = (double)filter.TurnoverTo.Value;
                turnoverQueries.Add(m => m.Range(p => p.Field(f => f.Turnover).LessThanOrEquals(turnoverTo)));
            }

            var employeeQueries = new List<Func<QueryContainerDescriptor<ElasticStatUnit>, QueryContainer>>();
            if (filter.EmployeesNumberFrom.HasValue)
            {
                int employeesNumberFrom = (int)filter.EmployeesNumberFrom.Value;
                employeeQueries.Add(m => m.Range(p => p.Field(f => f.Employees).GreaterThanOrEquals(employeesNumberFrom)));
            }
            if (filter.EmployeesNumberTo.HasValue)
            {
                int employeesNumberTo = (int)filter.EmployeesNumberTo.Value;
                employeeQueries.Add(m => m.Range(p => p.Field(f => f.Employees).LessThanOrEquals(employeesNumberTo)));
            }
            if (filter.Comparison == ComparisonEnum.And || turnoverQueries.Count == 0 || employeeQueries.Count == 0)
            {
                mustQueries.AddRange(turnoverQueries);
                mustQueries.AddRange(employeeQueries);
            }
            else
                mustQueries.Add(m => m.Bool(b => b.Should(s => s.Bool(b1 => b1.Must(turnoverQueries)), s => s.Bool(b2 => b2.Must(employeeQueries)))));

            if (filter.LastChangeFrom.HasValue)
            {
                DateTime lastChangeFrom = filter.LastChangeFrom.Value;
                mustQueries.Add(m => m.DateRange(p => p.Field(f => f.StartPeriod).GreaterThanOrEquals(lastChangeFrom)));
            }

            if (filter.LastChangeTo.HasValue)
            {
                DateTime lastChangeTo = filter.LastChangeTo.Value;
                mustQueries.Add(m => m.DateRange(p => p.Field(f => f.StartPeriod).LessThanOrEquals(lastChangeTo)));
            }

            if (filter.DataSourceClassificationId.HasValue)
            {
                int dataSourceClassificationId = filter.DataSourceClassificationId.Value;
                mustQueries.Add(m => m.Term(p => p.Field(f => f.DataSourceClassificationId).Value(dataSourceClassificationId)));
            }

            if (!filter.IncludeLiquidated)
                mustQueries.Add(m => m.Term(p => p.Field(f => f.IsLiquidated).Value(false)));

            if (filter.RegMainActivityId.HasValue)
            {
                var regMainActivityIds = new[] { filter.RegMainActivityId.Value };
                mustQueries.Add(m => m.Terms(p => p.Field(f => f.ActivityCategoryIds).Terms(regMainActivityIds)));
            }

            if (filter.SectorCodeId.HasValue)
            {
                int sectorCodeId = filter.SectorCodeId.Value;
                mustQueries.Add(m => m.Term(p => p.Field(f => f.SectorCodeId).Value(sectorCodeId)));
            }

            if (filter.LegalFormId.HasValue)
            {
                int legalFormId = filter.LegalFormId.Value;
                mustQueries.Add(m => m.Term(p => p.Field(f => f.LegalFormId).Value(legalFormId)));
            }

            if (isAdmin && filter.RegionId.HasValue)
            {
                int regionId = filter.RegionId.Value;
                mustQueries.Add(m => m.Term(p => p.Field(f => f.RegionId).Value(regionId)));
            }

            Func<SearchDescriptor<ElasticStatUnit>, ISearchRequest> searchFunc;
            if (filter.SortBy.HasValue)
                searchFunc = s => s.From(0).Take(10000).Query(q => q.Bool(b => b.Must(mustQueries)));
            else
                searchFunc = s => s.From((filter.Page - 1) * filter.PageSize).Take(filter.PageSize).Query(q => q.Bool(b => b.Must(mustQueries)));

            var searchResponse = await _elasticClient.SearchAsync(searchFunc);
            if (!searchResponse.IsValid)
                throw new Exception(searchResponse.DebugInformation);

            List<ElasticStatUnit> units = searchResponse.Documents.ToList();
            if (filter.SortBy.HasValue)
            {
                IOrderedEnumerable<ElasticStatUnit> sortQuery;
                switch (filter.SortBy.Value)
                {
                    case SortFields.Employees:
                        sortQuery = filter.SortRule == OrderRule.Asc ? units.OrderBy(u => u.Employees) : units.OrderByDescending(u => u.Employees);
                        break;
                    case SortFields.StatId:
                        sortQuery = filter.SortRule == OrderRule.Asc ? units.OrderBy(u => u.StatId) : units.OrderByDescending(u => u.StatId);
                        break;
                    case SortFields.Turnover:
                        sortQuery = filter.SortRule == OrderRule.Asc ? units.OrderBy(u => u.Turnover) : units.OrderByDescending(u => u.Turnover);
                        break;
                    default:
                        sortQuery = filter.SortRule == OrderRule.Asc ? units.OrderBy(u => u.Name) : units.OrderByDescending(u => u.Name);
                        break;
                }
                units = sortQuery.Skip((filter.Page - 1) * filter.PageSize).Take(filter.PageSize).ToList();
            }
            return SearchVm<ElasticStatUnit>.Create(units, searchResponse.Total);
        }
    }
}
