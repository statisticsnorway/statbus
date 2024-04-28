using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
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
using nscreg.Resources.Languages;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class ElasticService : IElasticUpsertService
    {
        public static string ServiceAddress { get; set; }
        public static string StatUnitSearchIndexName { get; set; }

        private static bool _isSynchronized;
        private static readonly SemaphoreSlim Semaphore = new SemaphoreSlim(1, 1);

        private readonly NSCRegDbContext _dbContext;
        private readonly ElasticClient _elasticClient;
        private readonly IMapper _mapper;

        public ElasticService(NSCRegDbContext dbContext, IMapper mapper)
        {
            _dbContext = dbContext;
            _mapper = mapper;

            var settings = new ConnectionSettings(new Uri(ServiceAddress)).DisableDirectStreaming();
            _elasticClient = new ElasticClient(settings);
        }
        public async Task Synchronize(bool force = false)
        {
            if (_isSynchronized && !force)
                return;
            try
            {
                await Semaphore.WaitAsync();
                if (_isSynchronized && !force)
                    return;

                var baseQuery = _dbContext.StatUnitSearchView;
                if (!force)
                {
                    int dbCount = await baseQuery.CountAsync();
                    var elasticsCount =
                        await _elasticClient.CountAsync<ElasticStatUnit>(c => c.Index(StatUnitSearchIndexName));

                    if (dbCount == elasticsCount.Count)
                    {
                        _isSynchronized = true;
                        return;
                    }
                }

                var deleteResponse = await _elasticClient.Indices.DeleteAsync(StatUnitSearchIndexName);
                if (!deleteResponse.IsValid && deleteResponse.ServerError.Error.Type != "index_not_found_exception")
                    throw new Exception(deleteResponse.DebugInformation);

                var activityCategoryStaticalUnits = (await _dbContext.ActivityStatisticalUnits
                        .Select(a => new {a.UnitId, a.Activity.ActivityCategoryId}).ToListAsync())
                    .ToLookup(a => a.UnitId, a => a.ActivityCategoryId);

                const int batchSize = 50000;

                var descriptor = new BulkDescriptor();

                int currentButchSize = 0;
                var query = baseQuery.AsNoTracking().AsEnumerable();

                foreach (var item in query)
                {
                    var elasticItem = _mapper.Map<StatUnitSearchView, ElasticStatUnit>(item);
                    elasticItem.ActivityCategoryIds = elasticItem.UnitType == StatUnitTypes.EnterpriseGroup
                        ? new List<int>()
                        : activityCategoryStaticalUnits[elasticItem.RegId].ToList();
                    descriptor.Index<ElasticStatUnit>(op => op.Index(StatUnitSearchIndexName).Document(elasticItem));
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

                _isSynchronized = true;
            }
            finally
            {
                Semaphore.Release(1);
            }
        }

        public async Task EditDocument(ElasticStatUnit elasticItem)
        {
            try
            {
                var updateResult = await _elasticClient.UpdateAsync<ElasticStatUnit, ElasticStatUnit>(elasticItem.Id,
                    u => u.Index(StatUnitSearchIndexName).Doc(elasticItem));
                if (!updateResult.IsValid)
                    throw new Exception(updateResult.DebugInformation);
            }
            catch
            {
                await Synchronize();
            }
        }

        /// <summary>
        /// Removing statunit from elastic
        /// </summary>
        /// <param name="statId">index of item in elastic</param>
        /// <param name="statUnitTypes">types of statunits</param>
        /// <returns></returns>
        public async Task DeleteDocumentAsync(ElasticStatUnit elasticItem)
        {
            try
            {
                var deleteResponse = await _elasticClient.DeleteAsync<ElasticStatUnit>(elasticItem.Id,
                    u => u.Index(StatUnitSearchIndexName));

                if (!deleteResponse.IsValid)
                {
                    throw new Exception(deleteResponse.DebugInformation);
                }
            }
            catch
            {
                await Synchronize();
            }
        }
        /// <summary>
        /// Removing statunit from elastic
        /// </summary>
        /// <param name="statId">index of item in elastic</param>
        /// <param name="statUnitTypes">types of statunits</param>
        /// <returns></returns>
        public async Task DeleteDocumentRangeAsync(IEnumerable<ElasticStatUnit> elasticItems)
        {
            try
            {
                var deleteResponse = await _elasticClient.DeleteManyAsync(elasticItems,StatUnitSearchIndexName);

                if (!deleteResponse.IsValid)
                {
                    throw new Exception(deleteResponse.DebugInformation);
                }
            }
            catch
            {
                await Synchronize();
            }
        }

        public async Task AddDocument(ElasticStatUnit elasticItem)
        {
            try
            {
                var insertResult = await _elasticClient.IndexAsync(elasticItem, i => i.Index(StatUnitSearchIndexName));
                if (!insertResult.IsValid)
                    throw new Exception(insertResult.DebugInformation);
            }
            catch
            {
                await Synchronize();
            }
        }

        public async Task<SearchVm<ElasticStatUnit>> Search(SearchQueryM filter, string userId, bool isDeleted)
        {
            await Synchronize();
            var mustQueries =
                new List<Func<QueryContainerDescriptor<ElasticStatUnit>, QueryContainer>>
                {
                    m => m.Term(p => p.Field(f => f.IsDeleted).Value(isDeleted))
                };

            var separators = new[] { ' ', '\t', '\r', '\n', ',', '.', '-' };

            if (!string.IsNullOrWhiteSpace(filter.Name))
            {
                var nameFilterParts = filter.Name.Replace("&", string.Empty).ToLower().Split(separators, StringSplitOptions.RemoveEmptyEntries);
                foreach (var nameFilter in nameFilterParts)
                    mustQueries.Add(m => m.Prefix(p => p.Field(f => f.Name).Value(nameFilter))
                                      || m.Prefix(p => p.Field(f => f.ShortName).Value(nameFilter))
                                      || m.Term(p => p.Field(f => f.StatId).Value(nameFilter))
                                      || m.Term(p => p.Field(f => f.RegId).Value(nameFilter))
                                      || m.Term(p => p.Field(f => f.TaxRegId).Value(nameFilter)));
            }

            if (filter.Type.Any())
                mustQueries.Add(m => m.Terms(p => p.Field(f => f.UnitType).Terms(filter.Type)));

            if (!string.IsNullOrWhiteSpace(filter.StatId))
                mustQueries.Add(m => m.Terms(p => p.Field(f => f.StatId).Terms(filter.StatId)));

            if (!string.IsNullOrWhiteSpace(filter.ExternalId))
                mustQueries.Add(m => m.Terms(p => p.Field(f => f.ExternalId).Terms(filter.ExternalId)));

            if (!string.IsNullOrWhiteSpace(filter.TaxRegId))
                mustQueries.Add(m => m.Terms(p => p.Field(f => f.TaxRegId).Terms(filter.TaxRegId)));

            if (!string.IsNullOrWhiteSpace(filter.Address))
            {
                string[] addressFilters = filter.Address.ToLower().Split(separators, StringSplitOptions.RemoveEmptyEntries);
                foreach (var addressFilter in addressFilters)
                {
                    mustQueries.Add(m => m
                        .Bool(b => b
                            .Should(s =>                                        
                                             s.Prefix(t => t.Field(f => f.ActualAddressPart1).Value(addressFilter))
                                            || s.Prefix(t => t.Field(f => f.ActualAddressPart2).Value(addressFilter))
                                            || s.Prefix(t => t.Field(f => f.ActualAddressPart3).Value(addressFilter)))
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
                DateTime lastChangeFrom = filter.LastChangeFrom.Value.ToUniversalTime();
                mustQueries.Add(m => m.DateRange(p => p.Field(f => f.StartPeriod).GreaterThanOrEquals(lastChangeFrom)));
            }

            if (filter.LastChangeTo.HasValue)
            {
                DateTime lastChangeTo = filter.LastChangeTo.Value.ToUniversalTime().AddHours(23).AddMinutes(59).AddSeconds(59);
                mustQueries.Add(m => m.DateRange(p => p.Field(f => f.StartPeriod).LessThanOrEquals(lastChangeTo)));
            }

            if (filter.LastChangeFrom.HasValue || filter.LastChangeTo.HasValue)
            {
                mustQueries.Add(m => m.Bool(b => b.MustNot(mn => mn.Term(p => p.Field(f => f.ChangeReason).Value(ChangeReasons.Create)))));
            }

            if (filter.DataSourceClassificationId.HasValue)
            {
                int dataSourceClassificationId = filter.DataSourceClassificationId.Value;
                mustQueries.Add(m => m.Term(p => p.Field(f => f.DataSourceClassificationId).Value(dataSourceClassificationId)));
            }

            if (!filter.IncludeLiquidated.HasValue || !filter.IncludeLiquidated.Value)
            {
                mustQueries.Add(m => !m.Exists(e => e.Field(f => f.LiqDate)));
            }
                
            if (filter.RegMainActivityId.HasValue)
            {
                var regMainActivityIds = new[] { filter.RegMainActivityId.Value };
                mustQueries.Add(m => m.Terms(p => p.Field(f => f.ActivityCategoryIds).Terms(regMainActivityIds)));
            }

            if (filter.RegId.HasValue)
            {
                int id = filter.RegId.Value;
                mustQueries.Add(m=>m.Term(p=>p.Field(f=>f.RegId).Value(id)));
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

            if (filter.RegionId.HasValue)
            {
                int regionId = filter.RegionId.Value;
                mustQueries.Add(m =>
                    m.Term(p => p.Field(f => f.RegionIds).Value(regionId)));
            }

            Func<SearchDescriptor<ElasticStatUnit>, ISearchRequest> searchFunc;
            if (filter.SortBy.HasValue)
                searchFunc = s =>
                    s.Index(StatUnitSearchIndexName).From(0).Take(10000).Query(q => q.Bool(b => b.Must(mustQueries))).TerminateAfter(2000);
            else
                searchFunc = s =>
                    s.Index(StatUnitSearchIndexName).From((filter.Page - 1) * filter.PageSize).Take(filter.PageSize)
                        .Query(q => q.Bool(b => b.Must(mustQueries))).TerminateAfter(2000);

            var searchResponse = await _elasticClient.SearchAsync(searchFunc);
            if (!searchResponse.IsValid)
                return SearchVm<ElasticStatUnit>.Create(new List<ElasticStatUnit>(), 0);
            //throw new Exception(searchResponse.DebugInformation);

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

        public async Task CheckElasticSearchConnection()
        {
            var connect = await _elasticClient.PingAsync();
            if (!connect.IsValid)
            {
                throw new NotFoundException(nameof(Resource.ElasticSearchIsDisable));
            }
        }

        public async Task UpsertDocumentList(List<ElasticStatUnit> elasticItems)
        {
            var bulkDescriptorBuffer = new BulkDescriptor();
            foreach (var item in elasticItems)
            {
                bulkDescriptorBuffer.Update<ElasticStatUnit>(op => op.Index(StatUnitSearchIndexName).Id(item.Id).Doc(item).DocAsUpsert());
            }

            var result = await _elasticClient.BulkAsync(bulkDescriptorBuffer);

            if (!result.IsValid)
                throw new Exception(result.DebugInformation);
        }
    }
}
